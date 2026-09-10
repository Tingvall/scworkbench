# Runtime license evidence

This directory retains upstream notices for dependencies whose installed
package metadata does not carry complete license files in the publication
containers. `runtime_license_manifest.json` binds each notice to the exact
source commit or release used by the runtime and records its SHA-256 digest.
The BPCells notices are byte-identical at the pinned R and Python commits;
both immutable upstream URLs are retained in the manifest.

The image build copies this directory to `/opt/scworkbench_runtime_licenses`
and validates both the files and installed package identities. These notices
supplement, rather than replace, package-manager and operating-system license
metadata already present in the image.
