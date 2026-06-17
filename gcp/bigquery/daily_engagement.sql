-- Replace `project-bc878e6c-6f53-4f24-88a` if you run this in another project.
CREATE OR REPLACE VIEW `project-bc878e6c-6f53-4f24-88a.navi_analytics.daily_engagement` AS
SELECT
  event_date,
  platform,
  COUNT(*) AS event_count,
  COUNT(DISTINCT firebase_uid_hash) AS active_users,
  COUNT(DISTINCT session_id) AS sessions,
  COUNTIF(event_name = 'journal_saved_locally') AS journal_saves,
  COUNTIF(event_name = 'audio_saved_locally') AS audio_saves,
  COUNTIF(event_name = 'audio_analysis_succeeded') AS audio_analysis_successes,
  COUNTIF(event_name = 'audio_analysis_failed') AS audio_analysis_failures,
  COUNTIF(event_name = 'insights_loaded') AS insight_loads,
  COUNTIF(event_name = 'data_export_requested') AS data_export_requests,
  COUNTIF(event_name = 'account_delete_started') AS account_delete_starts
FROM `project-bc878e6c-6f53-4f24-88a.navi_analytics.product_events`
GROUP BY event_date, platform;
