# WebDAV synchronization

Configure a WebDAV server that you control or are authorized to use. The application stores the URL and credentials locally according to the existing sync implementation; do not share those values in issue reports.

For troubleshooting, test the server URL, credentials, and read/write permissions separately before reporting an application problem.

## TXT source files and generated EPUB caches

TXT books use the original `.txt` file as the canonical book source. The source is stored under the application's `file/` directory and is the only TXT book file uploaded to WebDAV.

The EPUB generated for reading is a disposable local cache under the application cache directory:

```text
cache/txt_epub/<fingerprint>/generated.epub
```

The cache fingerprint includes the source MD5, the active chapter split rule, and the TXT parser version. If the cache is missing, corrupted, or its fingerprint no longer matches, it is regenerated on the device when the book is opened. A failed regeneration keeps the previous completed cache when one exists.

Releasing local space for a TXT book uploads the canonical TXT source first. Only after the upload succeeds does the application remove the local TXT and its safely identified local cache. An upload failure must leave the local source intact.

Existing EPUB files on the remote server are treated as historical compatibility artifacts during the source-only migration. This version does not automatically delete them. Review and cleanup of those files must be a separate, explicitly confirmed operation.

Legacy book records that contain only an EPUB `file_path` are not inferred to have originated from TXT. They continue to use the legacy EPUB synchronization behavior until the user explicitly re-imports a source file. The recommended migration path for a clean library is to remove old book records, install the new build, and import the original TXT/EPUB files again.
