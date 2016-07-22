# List NPM MOdules

This is a [node.js](http://nodejs.org/) command-line tool for node.js projects
that store their `node_modules/` directory in version control and install
packages manually, instead of using a `package.json` file to track
dependencies. It is intended to help such projects end up in a state where
they can use a `package.json` file.


## Setup

The recommended setup is cloning the repository and performing a local install.
This makes it easy to hack the code so it handles the special cases in your
project.

```bash
git clone https://github.com/pwnall/list-npm-modules.git
cd list-npm-modules
npm install -g --link
```


## Usage

List the node modules used by your project. The output is suitable for
inclusion in the `dependencies` or `devDependencies` section of `package.json`.

```bash
list-npm-modules
```

Go through the node modules in your project, and check if they carry patches.
This reinstalls the npm version of each module, and checks for differences
between the npm version and the version in your repository. Your code must be
in a git repository for this to work. The command outputs the modules that
carry patches.

```bash
list-npm-modules --find-patches
```

If you find yourself debugging a troublesome module, use the `--only` flag to
restrict any of the operations above to a single package.

```bash
list-npm-modules --only lodash
list-npm-modules --find-patches --only lodash
```


## License

This project is Copyright (c) 2016 Victor Costan, and distributed under the MIT
License.
