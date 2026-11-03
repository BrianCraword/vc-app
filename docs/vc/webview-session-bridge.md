# Authenticated web views: design, and what the source actually says

**Status:** design accepted, not built. No code yet.
**Why it exists:** Victorious Christians' matchmaking, Feed views, research
library and theme components cannot be rendered by a REST client. They are
served as web pages. To show them inside the app, a web view has to be
logged in as the member who is already signed into the app.

Every claim below was checked against Discourse `main` on 2026-11-02 and
against the live forum. Where the published specification and the source
disagree, the source wins and the disagreement is recorded.

---

## 1. The correction

An earlier estimate in chat said this was "the existing machinery pointed at
`/user-api-key/otp`, plus loading `/session/otp/<password>` in the web view" —
roughly twenty lines. **That was wrong, and it was wrong because it came from
the 2022 User API Keys specification on Discourse Meta rather than from the
code.**

Two things the specification does not say:

1. The spec describes `GET /user-api-key/otp` with a `User-Api-Key` header
   minting a one-time password directly. In current source that route renders
   an authorization page; the mint is a **separate POST action**
   (`create_otp`).
2. The spec does not mention that `/session/otp/:token` **only establishes a
   session on POST**. A GET renders a confirmation page and deliberately does
   not consume the token.

The second point is not an inconvenience to engineer around. See §4.

---

## 2. What the source establishes

| Question | Answer | Where |
|---|---|---|
| Routes for the login hop | `get` and `post` `session/otp/:token` → `session#one_time_password`, token constrained to hex | `config/routes.rb` |
| Does GET log you in? | No. GET renders a confirmation form. Only `request.post?` calls `log_on_user` | `session_controller.rb` |
| Is that POST exempt from CSRF? | **No.** `one_time_password` skips only `preload_json` and `check_xhr`. Forgery protection still applies | `session_controller.rb` |
| Token lifetime | Redis key `otp_<value>`, 10 minute expiry, deleted on successful login | `user_api_keys_controller.rb` |
| Which action mints | `create_otp`, requiring `public_key`, `auth_redirect`, `application_name`; optional `padding` of `pkcs1` or `oaep` | `user_api_keys_controller.rb` |
| Response shape | HTML request → redirect to `auth_redirect` with `oneTimePassword` appended. **JSON request → `{ redirect_url: ... }`** | `user_api_keys_controller.rb` |
| Encryption | `SecureRandom.hex`, encrypted to the supplied public key, `Base64.encode64` | `user_api_keys_controller.rb` |
| Who may mint | Staff, or a member of `user_api_key_allowed_groups`; and the site's `allow_user_api_key_scopes` must list `one_time_password` | `user_api_keys_controller.rb` |

### Does a `User-Api-Key` header satisfy `create_otp`?

Yes, on three separate checks, and none of them is the `one_time_password`
scope:

- **Authentication.** `DefaultCurrentUserProvider` resolves `User-Api-Key`
  (env `HTTP_USER_API_KEY`) to a user, so `requires_login` is satisfied.
- **CSRF.** `ApplicationController#handle_unverified_request` is a no-op when
  `is_user_api?`, which a `User-Api-Key` request sets. The documented reason is
  that the key is itself a secret.
- **Scope.** The key is checked with `ensure_allowed!`. Counter-intuitively,
  **`one_time_password` maps to an empty matcher list and permits nothing.**
  What permits the POST is the `write` scope, which matches any method on any
  action. `one_time_password` is a site-level permission flag read inside
  `create_otp`, not a route matcher.

That last row is the trap. Requesting `one_time_password` on the key is
necessary — the site setting is consulted — but it is `write` that gets the
request past the scope gate. A key minted with `one_time_password` alone would
be refused.

---

## 3. What the app already has

- `AppForumConfig.userApiRequestedScopes` already includes
  `one_time_password` **and** `write`. Every key already minted on this forum
  therefore carries both. Scopes are immutable once a key is issued, so had
  this not been requested from the start, every member would have had to sign
  in again. They do not.
- `DiscourseAuthManager` already owns RSA keypair generation, public-key PEM
  encoding, and `_decryptPayload`, which tries OAEP then falls back to
  PKCS1 v1.5 — exactly the two paddings `create_otp` accepts.
- `ThemedWebView` (forum_kit) already waits on the `forced_color_mode` cookie
  and covers the white first frame. `InAppWebViewPage` already wraps it.

So the new code is a mint-and-decrypt method on `DiscourseAuthManager` and an
authenticated page in `discourse_ui`. It is not twenty lines, but it is not a
new subsystem either.

**Constraint:** `forum_kit` must never import `discourse_core` — CI enforces
this. The authenticated wrapper therefore lives in `discourse_ui`, wrapping
`ThemedWebView`; it cannot be folded into `ThemedWebView` itself.

---

## 4. The confirmation screen stays

`GET /session/otp/:token` renders a form whose submit button reads from
`user_api_key.otp_confirmation.confirm_button`. Rails' `form_tag` supplies the
authenticity token the POST requires. The member taps it; the POST logs them
in and redirects to the forum root.

Auto-submitting that form with injected JavaScript was considered and
**rejected**, for two reasons.

The weaker reason is that it is fragile: the form has no `id`, the button's
only class is `btn btn-primary`, and the label is a translation key. A template
change upstream would break it silently, and silently here means a member
stranded on a page nobody explained.

The stronger reason is that the screen is doing a job. The attack it prevents
is forced login: someone mints a one-time password for *their* account, gets
the link in front of you, and your browser is now quietly signed in as them.
Everything you then write goes into their account. The confirmation is the step
where a human sees whose account is about to be used. Our own case is benign —
our token, our member, our web view — but writing code whose purpose is to
click past a consent screen is the wrong habit to establish in a community
application, and the benign case is exactly how such code gets written.

So it ships as a visible, deliberate step. It is survivable because **it is
once per install, not once per page**: the session cookie persists in the web
view's cookie jar, so every later page in the app is already authenticated.
Presented as a one-time "connect your account" step rather than an error, this
is unremarkable.

---

## 5. The flow

1. Member is signed in; the app holds a User API Key with `write` and
   `one_time_password`.
2. App generates a throwaway RSA keypair.
3. App POSTs `/user-api-key/otp` as JSON with the `User-Api-Key` header and
   `public_key`, `auth_redirect`, `application_name`, `padding=oaep`.
4. Response carries `redirect_url` with `oneTimePassword`. App base64-decodes
   and decrypts it to a hex token.
5. Web view opens `<forum>/session/otp/<token>`. Member taps confirm once.
6. Session cookie is set. App navigates to the target page. Every later web
   view in the app is already signed in.

Failure is not an error state: with no key, an expired token or a refusing
site, the web view simply opens the page signed out, which is what it does
today.

---

## 6. Open before building

- **`allow_user_api_key_scopes` on this forum must include
  `one_time_password`.** It is admin-only and is not in the public settings
  payload, so it could not be checked from outside. If it is absent,
  `create_otp` refuses and the whole bridge is dead until it is added.
  Admin → Settings → search "user api".
- **`user_api_key_allowed_groups`** must admit ordinary members. Almost
  certainly already true, since members can sign into the app at all, but it
  gates minting as well as issuing.
- Cookie persistence across app restarts on both platforms is assumed from
  `flutter_inappwebview`'s defaults and has not been measured. If it does not
  survive, the confirmation step becomes once per launch, which would change
  the recommendation in §4.
