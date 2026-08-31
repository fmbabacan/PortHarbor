# PortHarbor v1 Performance Record

Measurements were collected on the development Apple Silicon Mac from the installed PortHarbor 1.0.0 build. They are release evidence for acceptance criterion 13 and should be repeated on representative Apple Silicon and Intel hardware before a later performance-sensitive release.

## Results

- Cold build plus live listener discovery smoke: 15.33 seconds, including a clean Swift build.
- Live listener test execution after build: 0.36 seconds.
- Average CPU across five samples taken two seconds apart: 0.20 percent.
- Resident memory after launch and discovery: 112.6 MB.
- Installed application bundle: 2.8 MB.
- Main window: 1120 by 720 points, visible at layer 0 with full opacity.

## Assessment

- The average idle CPU target below 1 percent passed.
- The application bundle is compact.
- The observed 112.6 MB resident memory exceeds the v1 target of 80 MB.
- The memory result is accepted as a documented v1 exception. It does not block functional testing or safe operation, but memory profiling and reduction remain follow-up work.
- The live runtime test confirms that real listener discovery completes without being skipped.

The performance smoke script measures a clean build and live discovery path. The runtime and UI smoke suites provide separate evidence that listener discovery and visible-window launch work on the development Mac.
