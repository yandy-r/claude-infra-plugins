# yci:mop Error Messages

- **ID**: `mop-change-missing`
  - Meaning: `--change` was omitted or points to a missing file.

- **ID**: `mop-change-unsupported`
  - Meaning: Input shape is not one of the supported V1 MOP shapes.

- **ID**: `mop-change-malformed`
  - Meaning: The supplied change file parses, but not into the required schema.

- **ID**: `mop-vendor-missing-header`
  - Meaning: Vendor CLI input is missing the required `# vendor:` header.

- **ID**: `mop-vendor-unsupported`
  - Meaning: Vendor CLI input declared a vendor other than `iosxe` or `panos`.

- **ID**: `mop-format-unsupported`
  - Meaning: Requested output format is not supported in the markdown-first V1 flow.

- **ID**: `mop-branding-template-missing`
  - Meaning: `profile.deliverable.header_template` could not be resolved.

- **ID**: `mop-render-failed`
  - Meaning: The final MOP artifact template could not be rendered.

- **ID**: `mop-abort-criteria-failed`
  - Meaning: Abort-criteria derivation could not resolve required safety fields.

- **ID**: `mop-cross-customer-leak-detected`
  - Meaning: Cross-customer scanning detected foreign identifiers in the change or output.
