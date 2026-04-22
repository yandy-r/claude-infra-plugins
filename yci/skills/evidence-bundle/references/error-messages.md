# Evidence Bundle Error Messages

| Exit | ID                       | Meaning                                           |
| ---- | ------------------------ | ------------------------------------------------- |
| 1    | `eb-usage`               | Missing required flag or unknown argument         |
| 2    | `eb-profile-load-failed` | Active profile could not be resolved or parsed    |
| 3    | `eb-manifest-invalid`    | Manifest or stub parsing failed                   |
| 4    | `eb-adapter-invalid`     | Compliance adapter incomplete or missing          |
| 5    | `eb-validation-failed`   | Bundle failed schema or required-field validation |
| 6    | `eb-render-failed`       | Template rendering failed                         |
| 7    | `eb-signing-unavailable` | Requested signing backend is not installed        |
| 8    | `eb-signing-failed`      | Signing backend exited non-zero                   |

These IDs are emitted by `assemble-bundle.sh` and its helper scripts.
