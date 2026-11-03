# Android push notifications

EventHub uses Firebase Cloud Messaging (FCM) for Android push delivery and
Supabase Edge Functions to send pushes for announcements, organizer notices,
newly approved events, event updates, and registration status changes. Push delivery is separate from
the in-app notification feed; the feed continues to work if push is disabled.

Students receive newly approved event notices only when their grade/strand is
included in the event audience. Those notices appear in the in-app notification
bell for 14 days and open the event details from the Events tab. Check-in
confirmation taps use the same event-specific navigation.

## Firebase Android app setup

1. Create or select a Firebase project and add an Android app with package name
   `com.ianreyes132005.eventhub`.
2. Enable Firebase Cloud Messaging (HTTP v1) for the project.
3. Download that app's `google-services.json` to
   `android/app/google-services.json`. The Android Gradle build applies the
   Google Services plugin when this file exists. The file is intentionally
   ignored by Git.
4. Create a Firebase service-account key with permission to send FCM messages.
   Keep the JSON private; do not commit it.

## Supabase setup

1. Set the Edge Function secrets `FCM_SERVICE_ACCOUNT_JSON` (the complete
   service-account JSON) and `PUSH_WEBHOOK_SECRET` (a long random secret).
   Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to Edge
   Functions.
2. Deploy the function without JWT verification; it authenticates the
   database webhook using the separate secret header:

   ```text
   supabase functions deploy send-push --no-verify-jwt
   ```

3. Store the function URL and the same webhook secret in Supabase Vault:

   ```sql
   select vault.create_secret(
     'https://<project-ref>.supabase.co/functions/v1/send-push',
     'eventhub_push_function_url'
   );
   select vault.create_secret(
     '<same value as PUSH_WEBHOOK_SECRET>',
     'eventhub_push_webhook_secret'
   );
   ```

4. Run `supabase/migrations/202611030003_android_push_notifications.sql` in
   the Supabase SQL Editor. It creates device-token registration RPCs and
   database triggers for push-worthy changes.
5. Rebuild and install the Android app. After a successful login, EventHub
   asks for notification permission. If the user denies it, enable notifications
   for EventHub in Android Settings; the app avoids repeatedly prompting.
6. To notify students about newly approved events, also run
   `supabase/migrations/202611040001_student_event_push_notifications.sql`.

This implementation intentionally targets Android only. Firebase project
configuration, service-account credentials, Vault secrets, and the migration
must all be in place before outside-the-app notifications can be delivered.
