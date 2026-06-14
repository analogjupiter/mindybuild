/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	Common library of mindybuild.

	This module also contains the entry point for the CLI app.
 +/
module mindybuild.common;

version (MindybuildCommandLineApp) {
	mixin MindybuildCommandLineApp!();
}

mixin template MindybuildCommandLineApp() {
	private int main() {
		import mindybuild.common;
		
		return 1;
	}
}
