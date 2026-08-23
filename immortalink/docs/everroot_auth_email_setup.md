# Ever Roots production auth email setup

Status: preparation only. Do not commit SMTP credentials or API keys.

## Why this is needed

Supabase's default Auth mailer is not production-ready. It is restricted to
organization member email addresses and currently has a very low email send
limit. Ever Roots needs a custom SMTP provider before broad TestFlight signup,
password recovery, or public launch.

## Recommended provider

Start with Resend unless deliverability testing shows a problem.

Reasons:
- simple Supabase SMTP setup
- good developer workflow
- straightforward domain authentication
- enough scale for early TestFlight and launch

Good alternatives:
- Postmark for stronger transactional-email reputation and support
- AWS SES for lowest long-term unit cost, with more setup and operations work

## Sending identity

Use a dedicated auth sending subdomain and from-address:

- `auth.everroots.app`
- `no-reply@auth.everroots.app`

Keep auth email separate from marketing email. Do not put marketing copy,
multiple CTAs, or promotional images inside auth emails.

## DNS

Configure the records supplied by the SMTP provider:

- SPF
- DKIM
- DMARC

Recommended starting DMARC policy:

```text
v=DMARC1; p=none; rua=mailto:dmarc@everroots.app
```

After deliverability is verified, tighten DMARC gradually.

## Supabase dashboard steps

1. Go to Supabase Dashboard.
2. Open the production project.
3. Go to Authentication -> Emails -> SMTP Settings.
4. Enable custom SMTP.
5. Enter the provider SMTP host, port, username, password, sender name, and
   sender email.
6. Keep email confirmation enabled.
7. Confirm redirect URLs include the app's production web URL and native reset
   URL:
   - `com.everroots.app://login-callback/`
8. Send a test signup confirmation email.
9. Send a test password reset email.
10. Go to Authentication -> Rate Limits.
11. Start with an auth-email limit that matches early launch traffic, such as
    `100` emails/hour if the SMTP provider allows it.
12. Increase only after monitoring successful delivery and abuse patterns.

## App checks

The Flutter app should:
- keep users signed in by default
- avoid forcing repeated auth emails
- show friendly messages for SMTP/rate-limit failures
- avoid a resend button that can be spammed
- keep password reset redirects aligned with Supabase settings

## Launch test

Before public launch:

1. Create a new account with a non-team email address.
2. Confirm the email arrives.
3. Confirm the link opens the right app/web flow.
4. Use forgot password.
5. Confirm the reset link opens `ResetPasswordScreen`.
6. Set a new password.
7. Sign out and sign back in.
8. Confirm the app does not repeatedly ask returning users to request login
   emails.

## Never commit

- SMTP password
- SMTP API key
- Supabase service role key
- provider account credentials
- private DNS control credentials
