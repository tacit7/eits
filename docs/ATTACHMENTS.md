# File Attachment System

## Overview

The file attachment system allows users to attach files to messages in the EITS DM interface. Attachments are stored on disk and tracked in the database with metadata.

## Architecture

### Storage

Files are stored in the filesystem at:
```
priv/static/uploads/dm/YYYY-MM-DD/UUID.ext
```

Where:
- `YYYY-MM-DD` is the upload date
- `UUID` is a unique identifier generated at upload time
- `ext` is the original file extension

Files are served via Phoenix's static file handler and are accessible at:
```
/static/uploads/dm/YYYY-MM-DD/UUID.ext
```

### Database Schema

The `file_attachments` table tracks uploaded files:

| Column | Type | Purpose |
|--------|------|---------|
| id | integer | Primary key |
| uuid | uuid | Unique identifier |
| message_id | integer | FK to messages table |
| filename | string | Generated filename |
| original_filename | string | Name of file as uploaded |
| content_type | string | MIME type (e.g. image/png) |
| size_bytes | integer | File size in bytes |
| storage_path | string | Full filesystem path |
| upload_session_id | string | Session that uploaded the file |
| inserted_at | timestamp | Creation time |
| updated_at | timestamp | Last modification time |

Constraints:
- File size must be > 0 and ≤ 50MB
- All required fields: uuid, message_id, filename, original_filename, storage_path

### Allowed File Types

Only the following MIME types are allowed:
- Images: image/jpeg, image/png, image/gif
- Documents: application/pdf, text/plain
- Archives: application/zip, application/x-tar, application/gzip

## Usage

### Uploading Files

Files are uploaded through the message composer in the DM interface:
1. Click the + icon in the composer toolbar
2. Select file(s) to upload
3. Files appear as previews above the message input
4. Click the X button on a preview to remove before sending
5. Send the message — files are persisted after message creation

### Displaying Attachments

In the message view, attachments appear as cards showing:
- File icon
- Original filename (truncated if long)
- File size (KB/MB/B)
- Delete button (hover to reveal)

### Deleting Attachments

Users can delete attachments:
1. Hover over an attachment card in a message
2. Click the X button that appears
3. File is deleted from disk and database record removed

## Context Functions

### EyeInTheSky.FileAttachments

```elixir
# Create an attachment record
create_attachment(attrs :: map()) :: {:ok, FileAttachment.t()} | {:error, Changeset.t()}

# Delete an attachment (deletes file and DB record)
delete_attachment(attachment :: FileAttachment.t() | id :: integer()) 
  :: :ok | {:error, term()}
```

## LiveView Integration

### DmLive Events

```
"validate_upload" — Fires on file selection (currently no-op)
"cancel_upload" — Removes a pending upload by reference
"delete_attachment" — Deletes an existing attachment
```

### Message Handlers (MessageHandlers module)

- `handle_send_message/2` — Consumes uploaded files after message creation
- File processing happens in `DmLive.UploadHelpers`

### Components

- `DmMessageComponents.message_attachments/1` — Renders attachment list with delete buttons
- Shows filename, size, and delete button on hover

## Future Improvements

1. **Download Capability** — Add REST API endpoint to download files with proper content-type headers
2. **File Cleanup** — Periodic task to clean up orphaned files (attachments deleted but files remain)
3. **File Previews** — Thumbnail generation for images, PDF preview
4. **Attachment Permissions** — Control who can download/delete attachments
5. **Storage Backend** — Abstraction to support cloud storage (S3, GCS, etc.)
6. **Virus Scanning** — Scan uploaded files before persisting

## Security Considerations

1. **File Path Validation** — Always validate that storage_path is within the uploads directory
2. **Content-Type Validation** — Restricted to allowlist of safe types
3. **File Size Limits** — 50MB max enforced at schema level
4. **Access Control** — Only users in the message's session can delete attachments
5. **No Path Traversal** — Filenames are generated (UUIDs), not user-provided

## Error Handling

File deletion is resilient:
- If physical file is missing but DB record exists, record is still deleted
- Failed file deletion logs a warning but doesn't prevent DB cleanup
- DB errors during deletion are propagated to the caller
