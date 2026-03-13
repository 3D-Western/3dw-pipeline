# n8n Integration API Documentation

## Overview

This document provides comprehensive documentation for the n8n integration API, describing how n8n and the backend
coordinate job execution and cancellation.

**Base URL:** `http://localhost:8080`

**API Version:** v1

**Content Type:** `application/json`

**Authentication:** Service token-based authentication (opaque token)

**Target Audience:** n8n workflow/operations team and backend developers implementing integration endpoints

---

## Table of Contents

1. [Response Format](#response-format)
2. [Authentication](#authentication)
3. [High-Level Model](#high-level-model)
4. [Job States](#job-states)
5. [Jobs Resource](#jobs-resource)
6. [Cancellation Flow](#cancellation-flow)
7. [Error Responses](#error-responses)
8. [Error Codes Reference](#error-codes-reference)
9. [Additional Notes](#additional-notes)

---

## Response Format

All API responses follow a standardized structure to enable consistent error handling and type safety.

### Success Response Structure

```json
{
  "success": true,
  "data": {
    // Response data here
  }
}
```

### Error Response Structure

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {
      // Optional additional error details
    }
  }
}
```

---

## Authentication

All n8n → backend calls must include a **service token** in the request headers.

### Authentication Header

```
X-Service-Token: <opaque_token>
```

**Token Characteristics:**

- Opaque token (GitHub-style)
- Stored hashed in backend database
- Used exclusively for integration endpoints
- Separate from user session tokens

**Security:**

- Token must be kept secret
- Transmitted over HTTPS only
- Backend validates token on every request
- Invalid tokens result in `401 Unauthorized`

---

## High-Level Model

### ID Structure

The integration uses two distinct identifiers:

| ID Type       | Owner   | Format | Description                                           |
|---------------|---------|--------|-------------------------------------------------------|
| `jobId`       | Backend | UUID   | Internal execution record ID, created when job queues |
| `executionId` | n8n     | String | n8n's execution identifier, assigned when workflow starts |

**Why two IDs?**

- The backend creates a job record (`jobId`) before n8n even starts the workflow
- When n8n picks up the job and starts execution, it assigns its own `executionId`
- The `executionId` validation prevents race conditions if the same job gets re-triggered
- Backend controls `jobId`; n8n controls `executionId`

### Two Distinct Phases

The integration operates on **two distinct phases**:

### 1. Dispatch Accepted

- Backend triggers n8n workflow
- Job enters queue
- Execution may not have started yet
- No `n8n_execution_id` exists

### 2. Execution Started

- n8n worker picks up the job
- Execution ID is generated
- Job transitions to RUNNING state
- n8n can report progress and results

**Important:** Job state may exist without an n8n execution. Dispatch ≠ execution start.

---

## Job States

Job states are managed by the backend as the source of truth.

| State            | Meaning                                     | n8n Action                          |
|------------------|---------------------------------------------|-------------------------------------|
| QUEUED           | Job created, waiting to start               | Check status before starting        |
| RUNNING          | Execution started in n8n                    | Report progress, check cancellation |
| CANCEL_REQUESTED | User requested cancellation (pending)       | Stop execution, call `/canceled`    |
| CANCELED         | Execution confirmed stopped                 | No further action                   |
| SUCCEEDED        | Execution finished successfully             | No further action                   |
| FAILED           | Execution failed or terminated unexpectedly | No further action                   |

**Key Principle:** `CANCEL_REQUESTED` represents a pending cancel intent. n8n must cooperatively detect and honor
cancellation.

---

## Jobs Resource

Base Path: `/api/v1/integrations/n8n`

All endpoints below are under this prefix.

---

### 1. Execution Started

Mark a job as started when n8n workflow begins execution.

**Endpoint:**

```
POST /api/v1/integrations/n8n/jobs/{jobId}/started
```

**Authorization:** Service token required

**Use Case:**

- Call immediately when workflow actually starts running
- Execution ID must exist before calling
- Transitions job from QUEUED to RUNNING
- Records execution start time

**Path Parameters:**

- `jobId` (UUID) - Job identifier

**Request Body:**

```json
{
  "executionId": "123456",
  "workflowKey": "DEFECT_SCAN_V1",
  "startedAt": "2026-01-13T17:21:33.120Z"
}
```

**Required Fields:**

- `executionId` (string) - n8n execution identifier
- `workflowKey` (string) - Workflow type identifier
- `startedAt` (ISO 8601 datetime) - Execution start timestamp

**Response:** `200 OK`

```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "RUNNING",
    "executionId": "123456",
    "startedAt": "2026-01-13T17:21:33.120Z"
  }
}
```

**Error Responses:**

`401 Unauthorized` - Invalid or missing service token

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found` - Job not found

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

`409 Conflict` - Execution ID mismatch

```json
{
  "success": false,
  "error": {
    "code": "EXECUTION_ID_CONFLICT",
    "message": "Job already associated with different execution ID",
    "details": {
      "existingExecutionId": "123455",
      "providedExecutionId": "123456"
    }
  }
}
```

`400 Bad Request` - Validation errors

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Request validation failed",
    "details": {
      "executionId": "must not be blank",
      "startedAt": "must be a valid ISO 8601 datetime"
    }
  }
}
```

---

### 2. Progress Update (Optional)

Update job progress during long-running workflows.

**Endpoint:**

```
POST /api/v1/integrations/n8n/jobs/{jobId}/progress
```

**Authorization:** Service token required

**Use Case:**

- Call at safe checkpoints during workflow execution
- Backend responds with cancellation signal if needed
- Optional - only if progress tracking is required

**Path Parameters:**

- `jobId` (UUID) - Job identifier

**Request Body:**

```json
{
  "executionId": "123456",
  "progressPct": 42,
  "message": "Processing tiles"
}
```

**Required Fields:**

- `executionId` (string) - n8n execution identifier

**Optional Fields:**

- `progressPct` (integer, 0-100) - Completion percentage
- `message` (string) - Human-readable progress message

**Response:** `200 OK`

```json
{
  "success": true,
  "data": {
    "shouldCancel": false,
    "currentStatus": "RUNNING"
  }
}
```

**Response with Cancellation:**

```json
{
  "success": true,
  "data": {
    "shouldCancel": true,
    "currentStatus": "CANCEL_REQUESTED"
  }
}
```

**Important:** If `shouldCancel=true`, workflow must stop early and call `/canceled` endpoint.

**Error Responses:**

`401 Unauthorized`

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found`

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

`409 Conflict` - Execution ID mismatch

```json
{
  "success": false,
  "error": {
    "code": "EXECUTION_ID_CONFLICT",
    "message": "Execution ID does not match job record"
  }
}
```

---

### 3. Job Status Check (Cooperative Cancel)

Query current job status to detect cancellation requests.

**Endpoint:**

```
GET /api/v1/integrations/n8n/jobs/{jobId}/status?executionId=123456
```

**Authorization:** Service token required

**Use Case:**

- Call at workflow start and before expensive steps
- Detect pending cancellation intent
- Does not control execution directly, only reports state
- Enables cooperative cancellation pattern

**Path Parameters:**

- `jobId` (UUID) - Job identifier

**Query Parameters:**

- `executionId` (optional, string) - n8n execution identifier
    - If omitted, returns latest job status regardless of execution

**Response (continue):** `200 OK`

```json
{
  "success": true,
  "data": {
    "status": "RUNNING",
    "shouldCancel": false
  }
}
```

**Response (cancel requested):** `200 OK`

```json
{
  "success": true,
  "data": {
    "status": "CANCEL_REQUESTED",
    "shouldCancel": true
  }
}
```

**Workflow Action:** If `shouldCancel=true`, workflow must:

1. Stop execution safely
2. Clean up resources
3. Call `/canceled` endpoint

**Error Responses:**

`401 Unauthorized`

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found`

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

---

### 4. Execution Completed (Success)

Mark job as successfully completed.

**Endpoint:**

```
POST /api/v1/integrations/n8n/jobs/{jobId}/complete
```

**Authorization:** Service token required

**Use Case:**

- Call when workflow finishes successfully
- Finalizes job with SUCCEEDED state
- Persists result metadata

**Path Parameters:**

- `jobId` (UUID) - Job identifier

**Request Body:**

```json
{
  "executionId": "123456",
  "finishedAt": "2026-01-13T17:25:55.000Z",
  "result": {
    "resultRef": "s3://bucket/orders/42/output.json",
    "summary": {
      "defectsFound": 3
    }
  }
}
```

**Required Fields:**

- `executionId` (string) - n8n execution identifier
- `finishedAt` (ISO 8601 datetime) - Completion timestamp

**Optional Fields:**

- `result` (object) - Execution result metadata
    - `resultRef` (string) - Reference to result file/location
    - `summary` (object) - Arbitrary result summary data

**Response:** `200 OK`

```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "SUCCEEDED",
    "executionId": "123456",
    "startedAt": "2026-01-13T17:21:33.120Z",
    "finishedAt": "2026-01-13T17:25:55.000Z"
  }
}
```

**Error Responses:**

`401 Unauthorized`

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found`

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

`409 Conflict` - Execution ID mismatch

```json
{
  "success": false,
  "error": {
    "code": "EXECUTION_ID_CONFLICT",
    "message": "Execution ID does not match job record"
  }
}
```

`400 Bad Request` - Validation errors

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Request validation failed",
    "details": {
      "finishedAt": "must be a valid ISO 8601 datetime"
    }
  }
}
```

---

### 5. Execution Failed

Mark job as failed due to error or unexpected termination.

**Endpoint:**

```
POST /api/v1/integrations/n8n/jobs/{jobId}/failed
```

**Authorization:** Service token required

**Use Case:**

- Call when workflow errors or exits unexpectedly
- Finalizes job with FAILED state
- Persists error information

**Path Parameters:**

- `jobId` (UUID) - Job identifier

**Request Body:**

```json
{
  "executionId": "123456",
  "finishedAt": "2026-01-13T17:24:01.000Z",
  "error": {
    "code": "MODEL_ERROR",
    "message": "Out of memory"
  }
}
```

**Required Fields:**

- `executionId` (string) - n8n execution identifier
- `finishedAt` (ISO 8601 datetime) - Failure timestamp

**Optional Fields:**

- `error` (object) - Error details
    - `code` (string) - Error code
    - `message` (string) - Error message

**Response:** `200 OK`

```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "FAILED",
    "executionId": "123456",
    "startedAt": "2026-01-13T17:21:33.120Z",
    "finishedAt": "2026-01-13T17:24:01.000Z"
  }
}
```

**Error Responses:**

`401 Unauthorized`

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found`

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

`409 Conflict` - Execution ID mismatch

```json
{
  "success": false,
  "error": {
    "code": "EXECUTION_ID_CONFLICT",
    "message": "Execution ID does not match job record"
  }
}
```

---

### 6. Execution Canceled

Mark job as canceled after cooperative cancellation.

**Endpoint:**

```
POST /api/v1/integrations/n8n/jobs/{jobId}/canceled
```

**Authorization:** Service token required

**Use Case:**

- Call when workflow stops due to user cancellation
- Call after detecting `shouldCancel=true` from status check
- Finalizes job with CANCELED state

**Path Parameters:**

- `jobId` (UUID) - Job identifier

**Request Body:**

```json
{
  "executionId": "123456",
  "finishedAt": "2026-01-13T17:23:30.000Z",
  "reason": "User requested cancel"
}
```

**Required Fields:**

- `executionId` (string) - n8n execution identifier (may be omitted if job never started)
- `finishedAt` (ISO 8601 datetime) - Cancellation timestamp

**Optional Fields:**

- `reason` (string) - Cancellation reason

**Response:** `200 OK`

```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "CANCELED",
    "executionId": "123456",
    "startedAt": "2026-01-13T17:21:33.120Z",
    "finishedAt": "2026-01-13T17:23:30.000Z"
  }
}
```

**Error Responses:**

`401 Unauthorized`

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found`

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

`409 Conflict` - Execution ID mismatch (if provided)

```json
{
  "success": false,
  "error": {
    "code": "EXECUTION_ID_CONFLICT",
    "message": "Execution ID does not match job record"
  }
}
```

---

### 7. Manual Termination

Synchronize state after manual stop in n8n UI.

**Endpoint:**

```
POST /api/v1/integrations/n8n/jobs/{jobId}/terminated
```

**Authorization:** Service token required

**Use Case:**

- Call when execution is manually stopped by operator in n8n UI
- Synchronizes backend state with manual intervention
- Backend maps this to FAILED or CANCELED based on policy

**Termination Policy:**

The backend determines the final state based on the job's current status:

| Current Status     | Final State | Rationale                                    |
|--------------------|-------------|----------------------------------------------|
| `CANCEL_REQUESTED` | `CANCELED`  | User initiated cancellation, n8n honored it  |
| Any other state    | `FAILED`    | Unexpected termination (manual stop in n8n)  |

This distinction is useful for:
- **Auditing**: Distinguish intentional stops from unexpected terminations
- **Retry logic**: Auto-retry FAILED jobs but not CANCELED ones
- **Metrics**: Track "clean cancellations" vs "unexpected terminations"

**Path Parameters:**

- `jobId` (UUID) - Job identifier

**Request Body:**

```json
{
  "executionId": "123456",
  "terminatedAt": "2026-01-13T18:01:10.000Z",
  "reason": "Manually stopped in n8n UI"
}
```

**Required Fields:**

- `executionId` (string) - n8n execution identifier
- `terminatedAt` (ISO 8601 datetime) - Termination timestamp

**Optional Fields:**

- `reason` (string) - Termination reason

**Response:** `200 OK`

```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "FAILED",
    "executionId": "123456",
    "startedAt": "2026-01-13T17:21:33.120Z",
    "finishedAt": "2026-01-13T18:01:10.000Z"
  }
}
```

**Error Responses:**

`401 Unauthorized`

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found`

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

`409 Conflict` - Execution ID mismatch

```json
{
  "success": false,
  "error": {
    "code": "EXECUTION_ID_CONFLICT",
    "message": "Execution ID does not match job record"
  }
}
```

---

### 8. Request Presigned Upload URL

Request a presigned URL for n8n to upload result files directly to S3 storage.

**Endpoint:**

```
POST /api/v1/integrations/n8n/jobs/{jobId}/presigned-upload
```

**Authorization:** Service token required

**Use Case:**

- Call when n8n workflow needs to upload result files (e.g., processed models, reports, visualizations)
- Backend creates file record linked to n8n execution with UPLOADING status
- Generates presigned URL for direct upload to S3 (persistent storage)
- Result files are preserved long-term for user download

**Upload Flow:**

1. n8n requests presigned URL from backend
2. Backend creates file record linked to execution with UPLOADING status
3. Backend generates presigned S3 URL and returns it to n8n
4. n8n uploads file directly to S3 using presigned URL (PUT request)
5. n8n confirms upload completion with checksum
6. Backend verifies file exists in S3 and updates status to COMPLETED

**Path Parameters:**

- `jobId` (UUID) - Job identifier (print job ID, not n8n execution ID)

**Request Body:**

```json
{
  "executionId": "123456",
  "fileName": "processed_model.stl",
  "fileSize": 3457600,
  "contentType": "model/stl"
}
```

**Required Fields:**

- `executionId` (string) - n8n execution identifier (for verification)
- `fileName` (string) - Original filename (not blank)
- `fileSize` (long) - File size in bytes (minimum 1)
- `contentType` (string) - MIME type (not blank)

**Response:** `200 OK`

```json
{
  "success": true,
  "data": {
    "fileId": "550e8400-e29b-41d4-a716-446655440000",
    "presignedUrl": "https://s3.amazonaws.com/bucket/path?X-Amz-Algorithm=...",
    "expiresIn": 3600,
    "storageKey": "print-jobs/42/results/550e8400-e29b-41d4-a716-446655440000.stl"
  }
}
```

**Response Fields:**

- `fileId` (UUID) - File identifier for confirmation step
- `presignedUrl` (string) - Presigned URL for PUT upload to S3
- `expiresIn` (integer) - URL expiration time in seconds (3600 = 60 minutes)
- `storageKey` (string) - Storage path where file will be stored

**n8n Upload Instructions:**

After receiving the presigned URL:
1. Upload file directly to presigned URL using HTTP PUT
2. Calculate SHA-256 checksum of uploaded file
3. Call confirm upload endpoint with fileId and checksum

**Example Upload:**

```javascript
// Upload file to presigned URL
await axios.put(presignedUrl, fileBuffer, {
  headers: {
    'Content-Type': contentType
  }
});

// Calculate checksum
const checksum = crypto.createHash('sha256').update(fileBuffer).digest('hex');

// Confirm upload (see next endpoint)
```

**Error Responses:**

`400 Bad Request` - Validation errors

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Presigned upload request failed validation",
    "details": {
      "fileName": "must not be blank",
      "fileSize": "must be greater than 0"
    }
  }
}
```

`400 Bad Request` - Job not in RUNNING state

```json
{
  "success": false,
  "error": {
    "code": "INVALID_JOB_STATE",
    "message": "Job is not in RUNNING state: QUEUED"
  }
}
```

`401 Unauthorized`

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found` - Job not found

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

`409 Conflict` - Execution ID mismatch

```json
{
  "success": false,
  "error": {
    "code": "EXECUTION_ID_CONFLICT",
    "message": "Job already associated with different execution ID",
    "details": {
      "existingExecutionId": "123455",
      "providedExecutionId": "123456"
    }
  }
}
```

**Notes:**

- File record is created with UPLOADING status and linked to n8n execution
- Presigned URL expires after 60 minutes
- Files are stored in S3 (persistent storage) for long-term access
- Execution must be in RUNNING state to upload files
- File ownership is derived from the print job's user

---

### 9. Confirm Upload

Confirm completion of presigned URL upload and transition file to COMPLETED status.

**Endpoint:**

```
POST /api/v1/integrations/n8n/jobs/{jobId}/confirm-upload
```

**Authorization:** Service token required

**Use Case:**

- Call after successfully uploading file to presigned URL
- Verifies file exists in S3 storage
- Transitions file from UPLOADING to COMPLETED status
- Makes file available for user download

**Path Parameters:**

- `jobId` (UUID) - Job identifier (print job ID, not n8n execution ID)

**Request Body:**

```json
{
  "executionId": "123456",
  "fileId": "550e8400-e29b-41d4-a716-446655440000",
  "checksum": "a3b2c1d4e5f6789012345678901234567890123456789012345678901234abcd"
}
```

**Required Fields:**

- `executionId` (string) - n8n execution identifier (for verification)
- `fileId` (UUID) - File ID from presigned upload response
- `checksum` (string) - SHA-256 hash of uploaded file (64 hex characters)

**Response:** `200 OK`

```json
{
  "success": true,
  "data": {
    "message": "Upload confirmed successfully"
  }
}
```

**Error Responses:**

`400 Bad Request` - Invalid checksum format

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Upload confirmation failed validation",
    "details": {
      "checksum": "must be a valid SHA-256 hash (64 hex characters)"
    }
  }
}
```

`400 Bad Request` - File not in UPLOADING state

```json
{
  "success": false,
  "error": {
    "code": "INVALID_FILE_STATE",
    "message": "File is not in UPLOADING state: COMPLETED"
  }
}
```

`400 Bad Request` - File not found in storage

```json
{
  "success": false,
  "error": {
    "code": "FILE_NOT_IN_STORAGE",
    "message": "File not found in storage: print-jobs/42/results/550e8400.stl"
  }
}
```

`400 Bad Request` - File doesn't belong to execution

```json
{
  "success": false,
  "error": {
    "code": "FILE_EXECUTION_MISMATCH",
    "message": "File does not belong to this execution"
  }
}
```

`401 Unauthorized`

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing or invalid service token"
  }
}
```

`404 Not Found` - Job not found

```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "Job with ID 550e8400-e29b-41d4-a716-446655440000 not found"
  }
}
```

`404 Not Found` - File not found

```json
{
  "success": false,
  "error": {
    "code": "FILE_NOT_FOUND",
    "message": "File not found: 550e8400-e29b-41d4-a716-446655440000"
  }
}
```

`409 Conflict` - Execution ID mismatch

```json
{
  "success": false,
  "error": {
    "code": "EXECUTION_ID_CONFLICT",
    "message": "Execution ID does not match job record"
  }
}
```

**Notes:**

- Verifies file exists in S3 storage before confirming
- Updates file status from UPLOADING to COMPLETED
- Stores checksum for integrity verification
- Verifies file belongs to the correct n8n execution
- File becomes available for user download after confirmation

---

## Cancellation Flow

### User-Initiated Cancellation

**Backend Behavior:**

1. User clicks cancel in UI
2. Backend immediately sets job status to `CANCEL_REQUESTED`
3. Backend attempts to stop n8n execution (best-effort)
4. UI shows "Canceling..." state
5. Backend **never blocks** waiting for n8n confirmation

**n8n Workflow Behavior:**

n8n must cooperatively detect and handle cancellation through one of these patterns:

#### Pattern 1: Status Check (Recommended)

```
At workflow start and before expensive operations:
1. Call GET /jobs/{jobId}/status
2. If shouldCancel=true:
   - Stop execution
   - Clean up resources
   - Call POST /jobs/{jobId}/canceled
   - Exit workflow
```

#### Pattern 2: Progress Update

```
During long-running operations:
1. Call POST /jobs/{jobId}/progress
2. If response.shouldCancel=true:
   - Stop execution
   - Clean up resources
   - Call POST /jobs/{jobId}/canceled
   - Exit workflow
```

### Queued Job Cancellation

**Problem:** Job is queued but not yet started (no execution ID exists).

**Solution:**

1. Backend sets status to `CANCEL_REQUESTED`
2. When n8n eventually picks up the job:
    - Call `GET /jobs/{jobId}/status` (without executionId parameter)
    - Receive `shouldCancel=true`
    - Exit immediately without starting work
    - Call `POST /jobs/{jobId}/canceled` (without executionId)

**Benefit:** Guarantees correctness even if queue removal fails.

### Execution ID Safety Rule

For all callback endpoints:

- If `n8n_execution_id` is NULL → allow setting it
- If already set and different → return **409 Conflict**

This prevents stale or duplicate executions from overwriting newer attempts.

---

## Error Responses

All API error responses follow a standardized structure to enable consistent, programmatic error handling.

### Error Response Structure

Every error response contains:

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {
      // Optional additional context
    }
  }
}
```

**Fields:**

- `success` (boolean) - Always `false` for error responses
- `error.code` (string) - Machine-readable error code for programmatic handling
- `error.message` (string) - Human-readable error message for display or logging
- `error.details` (object, optional) - Additional context such as validation errors or debug information

### Common HTTP Status Codes

| Status Code                 | Description                               |
|-----------------------------|-------------------------------------------|
| `200 OK`                    | Request succeeded                         |
| `400 Bad Request`           | Invalid request format or validation fail |
| `401 Unauthorized`          | Missing or invalid service token          |
| `404 Not Found`             | Job does not exist                        |
| `409 Conflict`              | Execution ID mismatch or state conflict   |
| `500 Internal Server Error` | Unexpected server error                   |

---

## Error Codes Reference

This table lists all possible error codes returned by the n8n integration API for easy reference and programmatic error
handling.

| Error Code                 | HTTP Status | Description                            | Typical Use Case                               |
|----------------------------|-------------|----------------------------------------|------------------------------------------------|
| `UNAUTHORIZED`             | 401         | Missing or invalid service token       | No token or incorrect token provided           |
| `JOB_NOT_FOUND`            | 404         | Job with specified ID not found        | Invalid job ID in request                      |
| `FILE_NOT_FOUND`           | 404         | File with specified ID not found       | Invalid file ID in confirm upload request      |
| `EXECUTION_ID_CONFLICT`    | 409         | Execution ID does not match job record | Stale or duplicate execution attempting update |
| `VALIDATION_FAILED`        | 400         | Request failed validation              | Invalid or missing required fields             |
| `INVALID_STATUS`           | 400         | Invalid job status value               | Backend detected invalid state transition      |
| `INVALID_JOB_STATE`        | 400         | Job not in required state              | Attempting file upload when job not RUNNING    |
| `INVALID_FILE_STATE`       | 400         | File not in UPLOADING state            | Confirming upload for already completed file   |
| `FILE_NOT_IN_STORAGE`      | 400         | File not found in storage              | Confirming upload before file uploaded         |
| `FILE_EXECUTION_MISMATCH`  | 400         | File doesn't belong to execution       | File linked to different execution             |
| `INTERNAL_SERVER_ERROR`    | 500         | Unexpected server error                | Unhandled exception or system failure          |

---

## Additional Notes

### Backend as Source of Truth

- Backend maintains authoritative job state
- n8n reports execution lifecycle events
- Backend never queries n8n for state
- All state transitions are backend-controlled

### Dispatch vs Execution

- **Dispatch accepted** - Backend triggers n8n, job queued
- **Execution started** - n8n worker begins processing, execution ID exists
- These are separate phases
- Job state may exist without n8n execution

### Cancellation Guarantees

- Cancellation is **cooperative and best-effort**
- Backend signals intent via `CANCEL_REQUESTED` state
- n8n must actively check and honor cancellation
- Backend never blocks waiting for n8n confirmation
- Jobs may be queued, running, or canceled before start

### Workflow Integration Checklist

For n8n workflow developers, ensure your workflow:

1. ✅ Calls `/started` immediately when execution begins
2. ✅ Checks `/status` at workflow start and before expensive operations
3. ✅ Honors `shouldCancel=true` by stopping and calling `/canceled`
4. ✅ Uses `/presigned-upload` to request upload URLs for result files
5. ✅ Uploads files directly to presigned URLs (not through backend)
6. ✅ Calls `/confirm-upload` after successfully uploading each file
7. ✅ Calls `/complete` on successful completion
8. ✅ Calls `/failed` on errors or unexpected termination
9. ✅ Includes proper error handling and cleanup
10. ✅ Never updates backend database directly
11. ✅ Always includes service token in `X-Service-Token` header

### Service Token Security

- Service tokens must be stored securely in n8n credentials
- Transmitted only over HTTPS
- Separate from user session tokens
- Rotated periodically according to security policy
- Never logged or exposed in error messages

### Idempotency

All state transition endpoints (`/started`, `/complete`, `/failed`, `/canceled`) are designed to be idempotent:

- Safe to retry on network failure
- Execution ID conflict detection prevents double-processing
- Multiple calls with same data result in same final state

### Monitoring and Debugging

For operations teams:

- Monitor for jobs stuck in `RUNNING` state (execution may have died)
- Track cancellation response time (time from `CANCEL_REQUESTED` to `CANCELED`)
- Alert on frequent `EXECUTION_ID_CONFLICT` errors (may indicate retry issues)
- Log all n8n callback requests for audit trail

---

## Summary

### Key Principles

1. **Backend is source of truth** - All job state lives in backend
2. **n8n is execution engine** - Reports lifecycle events to backend
3. **Cancellation is cooperative** - n8n must actively check and honor
4. **Dispatch ≠ execution** - Jobs may be queued without execution ID
5. **State transitions are final** - Once SUCCEEDED/FAILED/CANCELED, job is complete

### Workflow Responsibilities

n8n workflows must:

- Report execution lifecycle (started, progress, complete/failed/canceled)
- Check for cancellation requests cooperatively
- Never update backend database directly
- Always finalize jobs with terminal state callback
- Handle errors gracefully and report failures

### Backend Responsibilities

Backend must:

- Maintain authoritative job state
- Accept and validate n8n callbacks
- Signal cancellation intent via status checks
- Enforce execution ID safety rules
- Never block on n8n responses
