![Banner](assets/banner.png)

![dart action](https://github.com/ShreyashSaitwal/rush-cli/actions/workflows/ci.yml/badge.svg) [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Rush is a new, and probably, improved way of building App Inventor 2 extensions. It is a build tool, which aims to improve the developer experience by reducing the boilerplate code and making extension development feel more like Android development.

Check out the [wiki section](https://github.com/ShreyashSaitwal/rush-cli/wiki) for a detailed overview and getting started with Rush.
Watch video turial on [Youtube](https://youtu.be/ngMutIRWKbw).

## Building from sources
1. Install [Dart SDK](https://dart.dev/get-dart).
2. Clone this repo: `git clone https://github.com/shreyashsaitwal/rush-cli`.
3. `cd` into the repo's base directory.
4. Run `dart pub get`.
5. Run the build script: `./scripts/build.sh -v VER_NAME`.
6. The generated executable can be found in `./build` directory.
