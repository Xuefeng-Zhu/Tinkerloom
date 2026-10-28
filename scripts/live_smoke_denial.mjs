/** Private row reads can be concealed as not found by Appwrite row security. */
const privateRowFields = new Set(["$id", "ownerId", "name", "rows"]);

export function containsPrivateRowFields(value) {
  const pending = [value];
  const visited = new Set();
  while (pending.length > 0) {
    const item = pending.pop();
    if (item === null || typeof item !== "object" || visited.has(item))
      continue;
    visited.add(item);
    for (const [key, child] of Object.entries(item)) {
      if (privateRowFields.has(key)) return true;
      pending.push(child);
    }
  }
  return false;
}

export function isPrivateRowReadDenied(
  result,
  { knownExistingRow = false } = {},
) {
  if (containsPrivateRowFields(result.data)) return false;
  if ([401, 403].includes(result.status)) return true;
  return (
    knownExistingRow === true &&
    result.status === 404 &&
    result.data?.type === "row_not_found"
  );
}
