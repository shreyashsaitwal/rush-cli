#!/usr/bin/env python3
import json
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
USAGE = 'usage: mkruntime.py <appinventor-dir> <ai2-version> <output-zip>'


def android_api_level(appinventor_dir):
    with open(os.path.join(appinventor_dir, 'components', 'build.xml')) as f:
        match = re.search(r'name="android.sdk.version"\s+value="(\d+)"', f.read())
    return int(match.group(1))


def always_included_jars(appinventor_dir):
    deps_dir = os.path.join(appinventor_dir, 'build', 'components', 'deps')
    with open(os.path.join(deps_dir, 'jars.txt')) as f:
        support_jars = {line.strip() for line in f if line.strip()}
    return support_jars | {'AndroidRuntime.jar', 'kawa.jar', 'android.jar'}


def runtime_jars(appinventor_dir):
    build_dir = os.path.join(appinventor_dir, 'build', 'components')
    deps_dir = os.path.join(build_dir, 'deps')
    jars = {'AndroidRuntime.jar': os.path.join(build_dir, 'AndroidRuntime.jar')}
    for name in sorted(os.listdir(deps_dir)):
        if name.endswith('.jar'):
            jars[name] = os.path.join(deps_dir, name)
    return jars


def main(appinventor_dir, ai2_version, output_zip):
    with open(os.path.join(HERE, 'coordinates.json')) as f:
        coordinates = json.load(f)

    jars = runtime_jars(appinventor_dir)
    always_included = always_included_jars(appinventor_dir)
    missing = sorted(set(coordinates) - set(jars))
    if missing:
        sys.exit(f'coordinates.json lists JARs missing from the build: {missing}')

    manifest = {
        'ai2Version': ai2_version,
        'androidApi': android_api_level(appinventor_dir),
        'libs': [{'file': f'libs/{name}',
                  'coordinate': coordinates.get(name),
                  'alwaysIncluded': name in always_included}
                 for name in jars],
    }

    with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('runtime.json', json.dumps(manifest, indent=2) + '\n')
        for name, path in jars.items():
            zf.write(path, f'libs/{name}')

    unmapped = sum(1 for lib in manifest['libs'] if lib['coordinate'] is None)
    print(f'{output_zip}: {len(jars)} libs, android-{manifest["androidApi"]}, '
          f'{unmapped} without Maven coordinates')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(USAGE)
    main(*sys.argv[1:])
