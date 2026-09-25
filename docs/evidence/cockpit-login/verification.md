# Cockpit login and study cards verification

Base revision: `c555de0`. Worktree change: form login backed by the existing `STUDY_COCKPIT_USERNAME` and `STUDY_COCKPIT_PASSWORD`, an encrypted Rails cookie session, and logout. No production deploy of the login change was performed.

## Expected outcomes and failure risks

- A browser without credentials sees a login form and remains outside protected routes; an invalid password is rejected.
- A valid login returns to the requested page, survives reload, and retains the same study-card learner identity and persisted progress. Logout removes browser access.
- Existing HTTP Basic clients remain usable. Mutating requests without a session do not reach the study-card action. Rails CSRF protection applies to login and logout forms.
- Cookie policy is `HttpOnly`, `SameSite=Lax`, 12-hour expiry, and `Secure` in production. Changing the configured username or password invalidates the old session cookie.

## Automated evidence

Before implementation, `bin/rails test test/system/cockpit_login_test.rb` failed at the first browser assertion: expected `Entrar no Study Cockpit`, but the HTTP Basic response had an empty page. The first sandboxed attempt could not connect to local PostgreSQL; the failing assertion above came from the actual Rails/ChromeDriver run with local database access.

After implementation:

```sh
bin/rails test test/controllers/cockpit_sessions_controller_test.rb test/system/cockpit_login_test.rb test/controllers/simulations_controller_test.rb test/controllers/study_cards_controller_test.rb test/system/study_cards_test.rb
```

Result before the credential-rotation guard: 11 runs, 81 assertions, 0 failures, 0 errors, 0 skips. After adding the guard, the expanded focused suite (including the library-card browser test) passed with 15 runs, 109 assertions, 0 failures, 0 errors, 0 skips. The suite uses local PostgreSQL and headless Chrome. A separate CSRF test enables Rails forgery protection, confirms a token in the form, and receives 422 for a POST without it.

The general Rails suite passed before the small rotation guard: 409 runs, 32,164 assertions, 0 failures, 0 errors, 0 skips. The focused suite passed after it. RuboCop inspected the seven changed Ruby files with no offenses, `bundle exec brakeman -q -w2` reported zero security warnings, and `git diff --check` passed.

Failure sensitivity was checked with temporary source mutations, each restored automatically: removing the cookie-session acceptance failed the browser flow; accepting any password failed two controller assertions; omitting `reset_session` on logout failed the revocation assertion; accepting any nonempty cookie verifier failed the password-rotation test.

## Real browser evidence

On September 25, 2026, Chrome with the user's existing production Basic Auth session opened `https://web-production-06974.up.railway.app/study-cards` (3,163 cards, 0 initially completed). The `System design · entrevistas` track opened a 36-card round. Its first question, `Design a URL shortener for us. Where do you want to start?`, revealed the original English Arcade answer beginning `Before components, I would clarify the dominant action`. The text matches `db/seeds/english_arcade/system-design.yml`. Clicking **Feito, próximo** changed the screen to `1 de 36` and the next question; reload retained both. The index showed 1 completed card and the resumable `1/36` round. Only an explicit click on **Repetir feitos** created a one-card replay round with the first question. In `Acervo · Chapters`, the Chapter 01 card revealed `Como um produto cresce sem transformar o banco relacional no vilao errado.`; the same text appeared in the linked full source document.

The production read created three persistent study-card rounds and marked one card completed in the authenticated learner's account. The production corpus count was 3,163 versus 3,188 in the local database; the reason for the difference was not established by this flow. No actual production password was requested or exposed.

The new form was then exercised against local Rails at `127.0.0.1:3117` in the Codex in-app browser using test credentials. An invalid password showed `Credenciais inválidas.`. A valid login reached `/study-cards` with 3,188 cards, survived reload, and displayed **Sair**. After logout, revisiting `/study-cards` returned to `/login`. The login page was visually inspected. This proves compatibility with the in-app browser locally; the production login remains unverified until this change is deployed.
