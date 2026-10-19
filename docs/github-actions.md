# GitHub Actions

## The project workflow

`rush create` adds `.github/workflows/build.yml` to new projects. Once the project is
pushed to GitHub, it:

- builds the extension on every push and pull request that changes the project
  (`rush.yml`, `src`, `assets`, `deps` or `res`), and uploads the `out` directory (the AIX
  and its documentation) as an artifact of the run;
- builds it on demand: open the **Actions** tab, choose **Build** and click **Run
  workflow**;
- publishes a release when a tag starting with `v` is pushed, with the AIX and its
  documentation attached and release notes generated from the commits.

To release, update `version` in `rush.yml`, commit, then tag that commit with the same
version:

```sh
git tag v1.2.0
git push origin v1.2.0
```

The release fails if the tag doesn't match `version`, so a release can't ship the wrong
version number.

Projects created by Rush 1 can copy the workflow:

```yaml
name: Build

on:
  push:
    paths:
      - rush.yml
      - src/**
      - assets/**
      - deps/**
      - res/**
  pull_request:
    paths:
      - rush.yml
      - src/**
      - assets/**
      - deps/**
      - res/**
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7
      - uses: shreyashsaitwal/rush-cli@v2
      - run: rush build
      - uses: actions/upload-artifact@v7
        with:
          name: ${{ github.event.repository.name }}
          path: out/
          if-no-files-found: error
      - name: Publish release
        if: startsWith(github.ref, 'refs/tags/v')
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          version=$(yq .version rush.yml)
          if [ "$GITHUB_REF_NAME" != "v$version" ]; then
            echo "::error::Tag $GITHUB_REF_NAME doesn't match version $version in rush.yml"
            exit 1
          fi
          gh release create "$GITHUB_REF_NAME" out/* --generate-notes
```

Change `rush build` to `rush build --optimize` to release optimized builds.

## The setup action

`shreyashsaitwal/rush-cli@v2` installs Rush in any workflow, on Linux, macOS and Windows
runners. It also sets up JDK 17 and caches the App Inventor runtime and Maven
dependencies between runs.

```yaml
- uses: shreyashsaitwal/rush-cli@v2
  with:
    version: 2.0.0
- run: rush build
```

| Input | |
|---|---|
| `version` | The Rush version to install. Defaults to the latest release |

| Output | |
|---|---|
| `version` | The installed Rush version |

`@v2` follows the latest 2.x release of the action.
