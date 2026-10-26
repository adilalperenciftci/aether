- **std.json exports the kinds `json.type` returns.** Its header listed
  `JSON_NULL` to `JSON_OBJECT`, but nothing defined them, so callers compared
  against the bare numbers 0 to 5. `json.JSON_NULL`, `json.JSON_BOOL`,
  `json.JSON_NUMBER`, `json.JSON_STRING`, `json.JSON_ARRAY` and
  `json.JSON_OBJECT` now exist, and std.jsonpath, std.schema, contrib/jq and
  the liquid templates use them (#3148).
