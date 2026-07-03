---
sidebar_position: 8
title: urltools
---

# urltools

Two tiny functions that remove a whole class of "open Python just to…" moments:

```text
$ urlencode 'stump rocks & other things'
stump%20rocks%20%26%20other%20things

$ urldecode 'https%3A%2F%2Foutline.stump.rocks%2Fdoc%2Fabc'
https://outline.stump.rocks/doc/abc
```

## Pro tips

- Pairs naturally with the **shlink** plugin: `shlink "$(urlencode-safe-url)"`
  when shortening URLs that contain query strings or spaces.
- `urldecode` is the fast way to read the real target out of tracking links and
  SSO redirect URLs before deciding whether to click.
- Both read from arguments, so command substitution works:
  `curl "https://api.example.com/?q=$(urlencode "$QUERY")"`.
- For JSON-specific escaping there's already `jsontools` (`urlencode_json`) —
  use urltools for plain strings, jsontools when the value lives inside JSON.
