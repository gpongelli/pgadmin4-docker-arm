import argparse
import json
import logging
import os
import re
from datetime import datetime
from functools import cmp_to_key
from io import BytesIO
from itertools import chain
from pathlib import Path

import docker
import docker.errors
import requests
import semver

from requests_html import HTMLSession
from python_active_versions.python_active_versions import get_active_python_versions


DOCKER_IMAGE_NAME = "gpongelli/pgadmin4-docker-armv7"
VERSIONS_PATH = Path("versions.json")
DEFAULT_DISTRO = ""
DISTROS = ["alpine"]
DEFAULT_DISTROS = ["alpine"]
DISTRO_TEMPLATE = {'alpine': 'raspberry'}

todays_date = datetime.utcnow().date().isoformat()


by_semver_key = cmp_to_key(semver.compare)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s - %(filename)s:%(lineno)d]    %(message)s',
    handlers=None,
)


def _latest_patch(tags, ver, patch_pattern, distro):
    tags = [tag for tag in tags if tag.startswith(ver) and tag.endswith(f"-{distro}") and patch_pattern.match(tag)]
    return sorted(tags, key=by_semver_key, reverse=True)[0] if tags else ""


def scrape_supported_pgadmin_versions():
    base_url = "https://www.postgresql.org/ftp/pgadmin/pgadmin4"
    versions = []
    version_table_selector = "#pgContentWrap table"
    detail_table_selector = "#pgFtpContent table"
    r = HTMLSession().get(base_url)
    version_table = r.html.find(version_table_selector, first=True)

    for ver in version_table.find("tr"):
        min_ver, = [v.text for v in ver.find("td")]
        if not min_ver.startswith('v'):  
            continue
        # dig deeper
        r_detail = HTMLSession().get(f'{base_url}/{min_ver}/pip')
        detail_table = r_detail.html.find(detail_table_selector, first=True)
        for row in detail_table.find("tr"):
            file, release_date, file_size = [r.text for r in row.find("td")]
            if not file.endswith('whl'):
                continue
            if min_ver.lstrip('v') < '6.0':
                continue
            logging.info("Found PgAdmin4 version: %s", min_ver)
            versions.append({
                "version_str": min_ver,
                "version": min_ver.lstrip('v'),
                "file_whl": file,
                "file_asc": file+'.asc',
                "release_date": release_date,
                "file_size": file_size
            })

    return versions


def decide_python_versions(distros):
    python_patch_re = "|".join([r"^(\d+\.\d+\.\d+-{})$".format(distro) for distro in distros])
    python_wanted_tag_pattern = re.compile(python_patch_re)

    # Skip unreleased and unsupported
    _python_versions = get_active_python_versions(docker_images=True)
    supported_versions = [v for v in _python_versions if v["start"] <= todays_date <= v["end"]]
    _lt = list(chain(*map(lambda x: x['docker_images'], supported_versions)))
    tags = [tag for tag in _lt if python_wanted_tag_pattern.match(tag)]

    versions = []
    for supported_version in supported_versions:
        ver = supported_version["version"]
        for distro in distros:
            canonical_image = _latest_patch(tags, ver, python_wanted_tag_pattern, distro)
            if not canonical_image:
                logging.info("Not good. ver=%s distro=%s not in tags, skipping...", ver, distro)
                continue
            canonical_version = canonical_image.replace(f"-{distro}", "")
            versions.append(
                {"canonical_version": canonical_version, "image": canonical_image, "key": ver, "distro": distro,
                 "start_date": supported_version["start"], "end_date": supported_version["end"]}
            )

    return sorted(versions, key=lambda v: by_semver_key(v["canonical_version"]), reverse=True)


def decide_pgadmin_versions():
    supported_versions = scrape_supported_pgadmin_versions()
    
    versions = supported_versions
    return versions


def version_combinations(pgadmin_versions, python_versions):
    versions = []
    for p in python_versions:
        for pg in pgadmin_versions:
            if pg["release_date"] < p["start_date"] or pg["release_date"] > p["end_date"]:
                continue
            distro = f'-{p["distro"]}' if p["distro"] != DEFAULT_DISTRO else ""
            key = f'{pg["version"]}-py{p["key"]}{distro}'
            versions.append(
                {
                    "key": key,
                    "python": p["key"],
                    "python_canonical": p["canonical_version"],
                    "python_image": p["image"],
                    "pgadmin": pg["version"],
                    "pgadmin_canonical": pg["version"]+".0",
                    "pgadmin_whl": pg["file_whl"],
                    "distro": p["distro"],
                }
            )

    versions = sorted(versions, key=lambda v: DISTROS.index(v["distro"]))
    versions = sorted(versions, key=lambda v: by_semver_key(v["python_canonical"]), reverse=True)
    versions = sorted(versions, key=lambda v: by_semver_key(v["pgadmin_canonical"]), reverse=True)
    return versions


def render_dockerfile(version):
    dockerfile_template = Path(f'template-{DISTRO_TEMPLATE[version["distro"]]}.Dockerfile').read_text()
    replace_pattern = re.compile("%%(.+?)%%")

    replacements = {"now": datetime.utcnow().isoformat()[:-7], **version}

    def repl(matchobj):
        key = matchobj.group(1).lower()
        return replacements[key]

    return replace_pattern.sub(repl, dockerfile_template)


def persist_versions(versions, dry_run=False):
    if dry_run:
        return
    with VERSIONS_PATH.open("w+") as fp:
        json.dump({"versions": versions}, fp, indent=2)


def load_versions():
    with VERSIONS_PATH.open() as fp:
        return json.load(fp)["versions"]


def build_new_or_updated(current_versions, versions, dry_run=False, debug=False):
    # Find new or updated
    current_versions = {ver["key"]: ver for ver in current_versions}
    versions = {ver["key"]: ver for ver in versions}
    new_or_updated = []

    for key, ver in versions.items():
        updated = key in current_versions and ver != current_versions[key]
        new = key not in current_versions
        if new or updated:
            new_or_updated.append(ver)

    if not new_or_updated:
        logging.info("No new or updated versions")
        return

    # Login to docker hub
    docker_client = docker.from_env()
    dockerhub_username = os.getenv("DOCKERHUB_USERNAME")
    try:
        docker_client.login(dockerhub_username, os.getenv("DOCKERHUB_PASSWORD"))
    except docker.errors.APIError:
        logging.error("Could not login to docker hub with username: %s", dockerhub_username)
        logging.error("Is env var DOCKERHUB_USERNAME and DOCKERHUB_PASSWORD set correctly?")
        exit(1)

    # Build, tag and push images
    failed_builds = []
    for version in new_or_updated:
        dockerfile = render_dockerfile(version)
        # docker build wants bytes
        with BytesIO(dockerfile.encode()) as fileobj:
            # save dockerfile to disk for building from path
            with Path(f"tmp.Dockerfile").open("w") as tmp_file:
                tmp_file.write(fileobj.read().decode("utf-8"))
            
            tag = f"{DOCKER_IMAGE_NAME}:{version['key']}"
            pgadmin_version = version["pgadmin"]
            python_version = version["python_canonical"]
            logging.info(
                "Building image %s pgadmin: %s python: %s ...",
                version['key'], pgadmin_version, python_version
            )
            try:
                if not dry_run:
                    docker_client.images.build(path=os.getcwd(),
                                               dockerfile="tmp.Dockerfile",
                                               tag=tag,
                                               rm=True,
                                               platform='linux/arm/v7',
                                               pull=True)
                if debug:
                    with Path(f"debug-{version['key']}.Dockerfile").open("w") as debug_file:
                        debug_file.write(fileobj.read().decode("utf-8"))
                logging.info(" pushing...")
                if not dry_run:
                    retries = 3
                    while retries > 0:
                        try:
                            docker_client.images.push(DOCKER_IMAGE_NAME, version["key"])
                            retries = 0
                        except requests.exceptions.ConnectionError as e:
                            logging.warning(e)
                            retries -= 1
                            logging.warning("Retrying... %s retries left", retries)
            except docker.errors.BuildError as e:
                logging.error("Failed building %s, skipping...", version)
                failed_builds.append(version)
    return failed_builds


def update_readme_tags_table(versions, dry_run=False):
    readme_path = Path("README.md")
    with readme_path.open() as fp:
        readme = fp.read()

    headings = [" Tag ", " pgAdmin version ", " Python version ", " Distro ", " Architecture "]

    def length_calc():
        table = [headings]
        for v in versions:
            table.append([f" `{v['key']}` ", v["pgadmin"], v["python_canonical"], f"{v['distro']}", "armv7"])
        _max = []

        for i in zip(*table):
            _max.append(max(list(map(lambda x: len(x), i))))

        return _max

    _widhts = length_calc()
    for h in range(0, len(headings)):
        # reformat header adding spaces for markdown
        headings[h] = f"{headings[h]:^{_widhts[h]}}"

    rows = []
    _architecture = 'armv7'
    for v in versions:
        _tmp_key = f" `{v['key']}` "
        rows.append([f"|{_tmp_key:^{_widhts[0]}}",
                     f"{v['pgadmin']:^{_widhts[1]}}",
                     f"{v['python_canonical']:^{_widhts[2]}}",
                     f"{v['distro']:^{_widhts[3]}}",
                     f"{_architecture:^{_widhts[4]}}|"])

    _sep = '-'
    head = f"|{'|'.join(headings)}|\n|{'|'.join([f'{_sep:-^{_widhts[h]}}' for h in range(0, len(headings))])}|"
    body = "\n".join(["|".join(row) for row in rows])
    table = f"{head}\n{body}\n"

    start = "the following table of available image tags.\n"
    end = "\nLovely!"
    sub_pattern = re.compile(f"{start}(.+?){end}", re.MULTILINE | re.DOTALL)

    readme_new = sub_pattern.sub(f"{start}\n{table}{end}", readme)
    if readme != readme_new and not dry_run:
        with readme_path.open("w+") as fp:
            fp.write(readme_new)


def save_latest_dockerfile(pgadmin_versions, distro=DEFAULT_DISTRO):
    # take template and render Dockerfile for latest version
    
    # take latest python version
    python_version = decide_python_versions([distro])[0]
    # tkae latest pgAdmin version
    pgadmin_version = pgadmin_versions[0]

    versions = version_combinations([pgadmin_version], [python_version])  # should be list of length 1; if invalid combination then length 0

    for version in versions:
        dockerfile = render_dockerfile(version)
        with BytesIO(dockerfile.encode()) as fileobj:
            # save dockerfile to disk for building from path
            with Path(f"Dockerfile").open("w") as tmp_file:
                tmp_file.write(fileobj.read().decode("utf-8"))


def main(distros, dry_run, debug):
    # distros = list(set(distros + [DEFAULT_DISTRO]))
    current_versions = load_versions()
    # Use latest patch version from each minor
    python_versions = decide_python_versions(distros)
    # Use latest minor version from each major
    pgadmin_versions = decide_pgadmin_versions()
    versions = version_combinations(pgadmin_versions, python_versions)

    # Build tag and release docker images
    failed_builds = build_new_or_updated(current_versions, versions, dry_run, debug)

    # persist image data after build ended
    persist_versions(versions, dry_run)
    update_readme_tags_table(versions, dry_run)
    save_latest_dockerfile(pgadmin_versions)

    # FIXME(perf): Generate a CircleCI config file with a workflow (parallell) and trigger this workflow via the API.
    # Ref: https://circleci.com/docs/2.0/api-job-trigger/
    # Ref: https://discuss.circleci.com/t/run-builds-on-circleci-using-a-local-config-file/17355?source_topic_id=19287


if __name__ == "__main__":
    parser = argparse.ArgumentParser(usage="🐳 Build pgAdmin4 docker images")
    parser.add_argument(
        "-d",
        "--distros",
        dest="distros",
        nargs="*",
        choices=DISTROS,
        help="Specify which distros to build",
        default=DEFAULT_DISTROS,
    )
    parser.add_argument(
        "--dry-run", action="store_true", dest="dry_run", help="Skip persisting, README update, and pushing of builds"
    )
    parser.add_argument("--debug", action="store_true", help="Write generated dockerfiles to disk")

    args = vars(parser.parse_args())
    main(**args)
