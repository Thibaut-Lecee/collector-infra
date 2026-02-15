#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-collector}"
JOB_NAME="${1:-}"
MANIFEST_PATH="${2:-}"

if [[ -z "${JOB_NAME}" || -z "${MANIFEST_PATH}" ]]; then
  echo "Usage: $0 <job-name> <manifest-path>"
  exit 2
fi

echo "Running k6 job '${JOB_NAME}' in namespace '${NAMESPACE}'"

kubectl -n "${NAMESPACE}" delete job "${JOB_NAME}" --ignore-not-found=true >/dev/null
kubectl apply -f "${MANIFEST_PATH}" >/dev/null

echo "Waiting for k6 pod to start..."
pod=""
for _ in $(seq 1 60); do
  pod="$(kubectl -n "${NAMESPACE}" get pods -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${pod}" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "${pod}" ]]; then
  echo "No pod found for job '${JOB_NAME}'"
  kubectl -n "${NAMESPACE}" get pods
  exit 1
fi

echo "Streaming logs from pod '${pod}' (Ctrl+C to stop logs only)..."

# Wait a bit for the container to start (image pulls can take a moment).
echo "Waiting for container to be running..."
kubectl -n "${NAMESPACE}" wait --for=jsonpath='{.status.phase}'=Running "pod/${pod}" --timeout=120s >/dev/null 2>&1 || true

set +e
kubectl -n "${NAMESPACE}" logs -f "${pod}" --pod-running-timeout=2m &
log_pid="$!"
trap 'echo "Stopping log stream..."; kill "${log_pid}" 2>/dev/null || true' INT

echo "Waiting for job to finish..."
job_result=""
for _ in $(seq 1 600); do
  succeeded="$(kubectl -n "${NAMESPACE}" get job "${JOB_NAME}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  failed="$(kubectl -n "${NAMESPACE}" get job "${JOB_NAME}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"

  if [[ "${succeeded}" == "1" ]]; then
    job_result="succeeded"
    break
  fi

  if [[ -n "${failed}" && "${failed}" != "0" ]]; then
    job_result="failed"
    break
  fi

  sleep 1
done

kill "${log_pid}" 2>/dev/null || true
wait "${log_pid}" 2>/dev/null
trap - INT
set -e

if [[ -z "${job_result}" ]]; then
  echo "Job '${JOB_NAME}' did not finish within 10 minutes"
  kubectl -n "${NAMESPACE}" describe job "${JOB_NAME}" || true
  exit 1
fi

echo "▶ Checking job status..."
succeeded="$(kubectl -n "${NAMESPACE}" get job "${JOB_NAME}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
failed="$(kubectl -n "${NAMESPACE}" get job "${JOB_NAME}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"

if [[ "${succeeded}" == "1" ]]; then
  echo "Job '${JOB_NAME}' completed successfully"
  exit 0
fi

echo "Job '${JOB_NAME}' failed (succeeded=${succeeded:-0} failed=${failed:-0})"
kubectl -n "${NAMESPACE}" describe job "${JOB_NAME}" || true
exit 1
