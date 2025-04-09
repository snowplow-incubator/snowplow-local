DROP VIEW IF EXISTS test_view;
-- recreate seed tables
DROP TABLE IF EXISTS unified_dim_geo_country_mapping;
DROP TABLE IF EXISTS unified_dim_rfc_5646_language_mapping;
DROP TABLE IF EXISTS unified_dim_iso_639_2t;
DROP TABLE IF EXISTS unified_dim_iso_639_3;
  
INSTALL iceberg;
LOAD iceberg;
create view test_view AS (SELECT * FROM iceberg_scan('./database/atomic/events/', metadata_compression_codec='gzip', allow_moved_paths=true));

-- create tables from seeds
create table unified_dim_geo_country_mapping AS (SELECT * FROM read_csv('https://raw.githubusercontent.com/snowplow/dbt-snowplow-unified/refs/heads/main/seeds/snowplow_unified_dim_geo_country_mapping.csv'));
create table unified_dim_rfc_5646_language_mapping AS (SELECT * FROM read_csv('https://raw.githubusercontent.com/snowplow/dbt-snowplow-unified/refs/heads/main/seeds/snowplow_unified_dim_rfc_5646_language_mapping.csv'));
create table unified_dim_iso_639_2t AS (SELECT * FROM read_csv('https://raw.githubusercontent.com/snowplow/dbt-snowplow-unified/refs/heads/main/seeds/snowplow_unified_dim_iso_639_2t.csv'));
create table unified_dim_iso_639_3 AS (SELECT * FROM read_csv('https://raw.githubusercontent.com/snowplow/dbt-snowplow-unified/refs/heads/main/seeds/snowplow_unified_dim_iso_639_3.csv'));

-- START: set your settings here
SET VARIABLE app_id = ['snowplow-local']; -- all app_ids if empty
SET VARIABLE heartbeat = 10; -- Page ping heartbeat time as defined in your tracker configuration.
SET VARIABLE min_visit_length = 5; -- Minimum visit length as defined in your tracker configuration.
SET VARIABLE ua_bot_filter = true; -- Filter bots (at the event level) based on a list of known bot user agents

-- entity feature toggles
SET VARIABLE enable_app_errors = false;
SET VARIABLE enable_application_context = false;
SET VARIABLE enable_browser_context = false;
SET VARIABLE enable_browser_context_2 = false;
SET VARIABLE enable_client_session_context = false; -- for user identifiers
SET VARIABLE enable_deep_link_context = false;
SET VARIABLE enable_geolocation_context = false;
SET VARIABLE enable_iab = false;
SET VARIABLE enable_mobile_context = false;
SET VARIABLE enable_screen_context = false;
SET VARIABLE enable_screen_summary_context = false;
SET VARIABLE enable_ua = false;
SET VARIABLE enable_web_page = true;
SET VARIABLE enable_yauaa = false;

-- END: settings

set variable q = '
  SELECT *, '
  || IF(GETVARIABLE('enable_app_errors'), 'contexts_com_snowplowanalytics_snowplow_application_error_1', '[]') || ' as contexts_com_snowplowanalytics_snowplow_application_error_1,'
  || IF(GETVARIABLE('enable_application_context'), 'contexts_com_snowplowanalytics_mobile_application_1', '[]') || ' as contexts_com_snowplowanalytics_mobile_application_1,'
  || IF(GETVARIABLE('enable_browser_context'), 'contexts_com_snowplowanalytics_snowplow_browser_context_1', '[]') || ' as contexts_com_snowplowanalytics_snowplow_browser_context_1,'
  || IF(GETVARIABLE('enable_browser_context_2'), 'contexts_com_snowplowanalytics_snowplow_browser_context_2', '[]') || ' as contexts_com_snowplowanalytics_snowplow_browser_context_2,'
  || IF(GETVARIABLE('enable_client_session_context'), 'contexts_com_snowplowanalytics_snowplow_client_session_1', '[]') || ' as contexts_com_snowplowanalytics_snowplow_client_session_1,'
  || IF(GETVARIABLE('enable_deep_link_context'), 'contexts_com_snowplowanalytics_mobile_deep_link_1', '[]') || ' as contexts_com_snowplowanalytics_mobile_deep_link_1,'
  || IF(GETVARIABLE('enable_geolocation_context'), 'contexts_com_snowplowanalytics_snowplow_geolocation_context_1', '[]') || ' as contexts_com_snowplowanalytics_snowplow_geolocation_context_1,'
  || IF(GETVARIABLE('enable_iab'), 'contexts_com_iab_snowplow_spiders_and_robots_1', '[]') || ' as contexts_com_iab_snowplow_spiders_and_robots_1,'
  || IF(GETVARIABLE('enable_mobile_context'), 'contexts_com_snowplowanalytics_snowplow_mobile_context_1', '[]') || ' as contexts_com_snowplowanalytics_snowplow_mobile_context_1,'
  || IF(GETVARIABLE('enable_mobile_context'), 'unstruct_event_com_snowplowanalytics_mobile_screen_view_1', 'struct_pack(k:= 1)') || ' as unstruct_event_com_snowplowanalytics_mobile_screen_view_1,'
  || IF(GETVARIABLE('enable_screen_context'), 'contexts_com_snowplowanalytics_mobile_screen_1', '[]') || ' as contexts_com_snowplowanalytics_mobile_screen_1,'
  || IF(GETVARIABLE('enable_screen_summary_context'), 'contexts_com_snowplowanalytics_mobile_screen_summary_1', '[]') || ' as contexts_com_snowplowanalytics_mobile_screen_summary_1,'
  || IF(GETVARIABLE('enable_ua'), 'contexts_com_snowplowanalytics_snowplow_ua_parser_context_1', '[]') || ' as contexts_com_snowplowanalytics_snowplow_ua_parser_context_1,'
  || IF(GETVARIABLE('enable_web_page'), 'contexts_com_snowplowanalytics_snowplow_web_page_1', '[]') || ' as contexts_com_snowplowanalytics_snowplow_web_page_1,'
  || IF(GETVARIABLE('enable_yauaa'), 'contexts_nl_basjes_yauaa_context_1', '[]') || ' as contexts_nl_basjes_yauaa_context_1'
  || ' FROM test_view'
  || IF(LEN(GETVARIABLE('app_id')) != 0, ' WHERE app_id IN ' || list_transform(getvariable('app_id'), x -> '''' || x || '''')::varchar, '' );

select getvariable('q');
drop view if exists refined;
create view refined AS (SELECT * from query(getvariable('q')));

-- START: Unified events

DROP VIEW IF EXISTS unified_events; -- drop existing view if required

CREATE VIEW unified_events AS
WITH identified_events AS (
    SELECT
        COALESCE(
            COALESCE(contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'sessionId', NULL),
            domain_sessionid, 
            NULL
        ) AS session_identifier,
        *
    FROM refined
),
base_query AS (
    SELECT
        a.*,
        a.domain_userid AS user_identifier,
    FROM identified_events a
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.event_id ORDER BY a.collector_tstamp, a.dvce_created_tstamp) = 1
),

base_query_2 AS (
    SELECT
        *
    , contexts_com_snowplowanalytics_snowplow_web_page_1[1]->>'id' AS page_view__id
  
  , contexts_com_iab_snowplow_spiders_and_robots_1[1]->>'category' AS iab__category
  , contexts_com_iab_snowplow_spiders_and_robots_1[1]->>'primary_impact' AS iab__primary_impact
  , contexts_com_iab_snowplow_spiders_and_robots_1[1]->>'reason' AS iab__reason
  , try_cast(contexts_com_iab_snowplow_spiders_and_robots_1[1]->>'spider_or_robot' AS BOOLEAN) AS iab__spider_or_robot

  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'useragent_family' AS ua__useragent_family
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'useragent_major' AS ua__useragent_major
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'useragent_minor' AS ua__useragent_minor
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'useragent_patch' AS ua__useragent_patch
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'useragent_version' AS ua__useragent_version
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'os_family' AS ua__os_family
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'os_major' AS ua__os_major
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'os_minor' AS ua__os_minor
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'os_patch' AS ua__os_patch
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'os_patch_minor' AS ua__os_patch_minor
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'os_version' AS ua__os_version
  , contexts_com_snowplowanalytics_snowplow_ua_parser_context_1[1]->>'device_family' AS ua__device_family

  , contexts_nl_basjes_yauaa_context_1[1]->>'device_class' AS yauaa__device_class
  , contexts_nl_basjes_yauaa_context_1[1]->>'agent_class' AS yauaa__agent_class
  , contexts_nl_basjes_yauaa_context_1[1]->>'agent_name' AS yauaa__agent_name
  , contexts_nl_basjes_yauaa_context_1[1]->>'agent_name_version' AS yauaa__agent_name_version
  , contexts_nl_basjes_yauaa_context_1[1]->>'agent_name_version_major' AS yauaa__agent_name_version_major
  , contexts_nl_basjes_yauaa_context_1[1]->>'agent_version' AS yauaa__agent_version
  , contexts_nl_basjes_yauaa_context_1[1]->>'agent_version_major' AS yauaa__agent_version_major
  , contexts_nl_basjes_yauaa_context_1[1]->>'device_brand' AS yauaa__device_brand
  , contexts_nl_basjes_yauaa_context_1[1]->>'device_name' AS yauaa__device_name
  , contexts_nl_basjes_yauaa_context_1[1]->>'device_version' AS yauaa__device_version
  , contexts_nl_basjes_yauaa_context_1[1]->>'layout_engine_class' AS yauaa__layout_engine_class
  , contexts_nl_basjes_yauaa_context_1[1]->>'layout_engine_name' AS yauaa__layout_engine_name
  , contexts_nl_basjes_yauaa_context_1[1]->>'layout_engine_name_version' AS yauaa__layout_engine_name_version
  , contexts_nl_basjes_yauaa_context_1[1]->>'layout_engine_name_version_major' AS yauaa__layout_engine_name_version_major
  , contexts_nl_basjes_yauaa_context_1[1]->>'layout_engine_version' AS yauaa__layout_engine_version
  , contexts_nl_basjes_yauaa_context_1[1]->>'layout_engine_version_major' AS yauaa__layout_engine_version_major
  , contexts_nl_basjes_yauaa_context_1[1]->>'operating_system_class' AS yauaa__operating_system_class
  , contexts_nl_basjes_yauaa_context_1[1]->>'operating_system_name' AS yauaa__operating_system_name
  , contexts_nl_basjes_yauaa_context_1[1]->>'operating_system_name_version' AS yauaa__operating_system_name_version
  , contexts_nl_basjes_yauaa_context_1[1]->>'operating_system_version' AS yauaa__operating_system_version

  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'viewport' AS browser__viewport
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'document_size' AS browser__document_size
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'resolution' AS browser__resolution
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'color_depth'::INT AS browser__color_depth
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'device_pixel_ratio' AS browser__device_pixel_ratio
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'cookies_enabled' AS browser__cookies_enabled
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'online' AS browser__online
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'browser_language' AS browser__browser_language
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'document_language' AS browser__document_language
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'webdriver' AS browser__webdriver
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'device_memory' AS browser__device_memory
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'hardware_concurrency' AS browser__hardware_concurrency
  , contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'tab_id' AS browser__tab_id


  , unstruct_event_com_snowplowanalytics_mobile_screen_view_1->>'id' AS screen_view__id
  , unstruct_event_com_snowplowanalytics_mobile_screen_view_1->>'name' AS screen_view__name
  , unstruct_event_com_snowplowanalytics_mobile_screen_view_1->>'previous_id' AS screen_view__previous_id
  , unstruct_event_com_snowplowanalytics_mobile_screen_view_1->>'previous_name' AS screen_view__previous_name
  , unstruct_event_com_snowplowanalytics_mobile_screen_view_1->>'previous_type' AS screen_view__previous_type
  , unstruct_event_com_snowplowanalytics_mobile_screen_view_1->>'transition_type' AS screen_view__transition_type
  , unstruct_event_com_snowplowanalytics_mobile_screen_view_1->>'type' AS screen_view__type
  
  , contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'session_id' AS session__session_id
  , contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'session_index' AS session__session_index
  , contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'previous_session_id' AS session__previous_session_id
  , contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'user_id' AS session__user_id
  , contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'first_event_id' AS session__first_event_id
  , contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'event_index' AS session__event_index
  , contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'storage_mechanism' AS session__storage_mechanism
  , contexts_com_snowplowanalytics_snowplow_client_session_1[1]->>'first_event_timestamp' AS session__first_event_timestamp



        , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'device_manufacturer' AS mobile__device_manufacturer
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'device_model' AS mobile__device_model
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'os_type' AS mobile__os_type
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'os_version' AS mobile__os_version
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'android_idfa' AS mobile__android_idfa
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'apple_idfa' AS mobile__apple_idfa
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'apple_idfv' AS mobile__apple_idfv
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'carrier' AS mobile__carrier
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'open_idfa' AS mobile__open_idfa
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'network_technology' AS mobile__network_technology
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'network_type' AS mobile__network_type
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'physical_memory' AS mobile__physical_memory
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'system_available_memory' AS mobile__system_available_memory
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'app_available_memory' AS mobile__app_available_memory
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'battery_level' AS mobile__battery_level
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'battery_state' AS mobile__battery_state
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'low_power_mode' AS mobile__low_power_mode
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'available_storage' AS mobile__available_storage
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'total_storage' AS mobile__total_storage
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'is_portrait' AS mobile__is_portrait
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'resolution' AS mobile__resolution
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'scale' AS mobile__scale
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'language' AS mobile__language
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'app_set_id' AS mobile__app_set_id
      , contexts_com_snowplowanalytics_snowplow_mobile_context_1[1]->>'app_set_id_scope' AS mobile__app_set_id_scope

      , contexts_com_snowplowanalytics_snowplow_geolocation_context_1[1]->>'latitude' AS geo__latitude
      , contexts_com_snowplowanalytics_snowplow_geolocation_context_1[1]->>'longitude' AS geo__longitude
      , contexts_com_snowplowanalytics_snowplow_geolocation_context_1[1]->>'latitude_longitude_accuracy' AS geo__latitude_longitude_accuracy
      , contexts_com_snowplowanalytics_snowplow_geolocation_context_1[1]->>'altitude' AS geo__altitude
      , contexts_com_snowplowanalytics_snowplow_geolocation_context_1[1]->>'altitude_accuracy' AS geo__altitude_accuracy
      , contexts_com_snowplowanalytics_snowplow_geolocation_context_1[1]->>'bearing' AS geo__bearing
      , contexts_com_snowplowanalytics_snowplow_geolocation_context_1[1]->>'speed' AS geo__speed

      , contexts_com_snowplowanalytics_mobile_application_1[1]->>'build' AS app__build
      , contexts_com_snowplowanalytics_mobile_application_1[1]->>'version' AS app__version

      , contexts_com_snowplowanalytics_mobile_screen_1[1]->>'id' AS screen__id
      , contexts_com_snowplowanalytics_mobile_screen_1[1]->>'name' AS screen__name
      , contexts_com_snowplowanalytics_mobile_screen_1[1]->>'activity' AS screen__activity
      , contexts_com_snowplowanalytics_mobile_screen_1[1]->>'fragment' AS screen__fragment
      , contexts_com_snowplowanalytics_mobile_screen_1[1]->>'top_view_controller' AS screen__top_view_controller
      , contexts_com_snowplowanalytics_mobile_screen_1[1]->>'type' AS screen__type
      , contexts_com_snowplowanalytics_mobile_screen_1[1]->>'view_controller' AS screen__view_controller

      , contexts_com_snowplowanalytics_mobile_deep_link_1[1]->>'url' AS deep_link__url
      , contexts_com_snowplowanalytics_mobile_deep_link_1[1]->>'referrer' AS deep_link__referrer

      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'viewport', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'viewport') AS browser__viewport
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'document_size', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'document_size') AS browser__documentSize
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'resolution', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'resolution') AS browser__resolution
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'color_depth', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'color_depth') AS browser__colorDepth
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'device_pixel_ratio', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'device_pixel_ratio') AS browser__devicePixelRatio
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'cookies_enabled', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'cookies_enabled') AS browser__cookiesEnabled
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'online', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'online') AS browser__online
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'browser_language', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'browser_language') AS browser__browserLanguage
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'document_language', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'document_language') AS browser__documentLanguage
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'webdriver', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'webdriver') AS browser__webdriver
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'device_memory', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'device_memory') AS browser__deviceMemory
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'hardware_concurrency', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'hardware_concurrency') AS browser__hardwareConcurrency
      , COALESCE(contexts_com_snowplowanalytics_snowplow_browser_context_1[1]->>'tab_id', contexts_com_snowplowanalytics_snowplow_browser_context_2[1]->>'tab_id') AS browser__tabId

      -- screen summary
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'foreground_sec' AS screen_summary__foreground_sec
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'background_sec' AS screen_summary__background_sec
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'last_item_index' AS screen_summary__last_item_index
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'items_count' AS screen_summary__items_count
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'min_x_offset' AS screen_summary__min_x_offset
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'min_y_offset' AS screen_summary__min_y_offset
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'max_x_offset' AS screen_summary__max_x_offset
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'max_y_offset' AS screen_summary__max_y_offset
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'content_width' AS screen_summary__content_width
    , contexts_com_snowplowanalytics_mobile_screen_summary_1[1]->>'content_height' AS screen_summary__content_height
  
    FROM base_query
),
base as (

    select
      *,
      cast(coalesce(
          ev.page_view__id,
          ev.screen_view__id,
          ev.screen__id,
        null, null) as TEXT ) as view_id,
        cast(coalesce(
          ev.session__session_index::int,
          ev.domain_sessionidx,
        null, null) as INT ) as device_session_index,
      cast(coalesce(
          ev.deep_link__referrer,
        null, null) as TEXT ) as referrer,
      cast(coalesce(
          ev.deep_link__url,
        null, null) as TEXT ) as url,
      cast(coalesce(
          ev.mobile__resolution,
        null, null) as TEXT ) as screen_resolution,
      cast(coalesce(
          ev.mobile__os_type,
          ev.yauaa__operating_system_name,
          ev.ua__os_family,
        null, null) as TEXT ) as os_type,
      cast(coalesce(
          ev.yauaa__operating_system_version,
          ev.mobile__os_version,
          ev.ua__os_version,
        null, null) as TEXT ) as os_version,
      cast(coalesce(
          ev.domain_userid,
          ev.session__user_id,
        null, null) as TEXT ) as device_identifier,
      case when platform = 'web' then 'Web' --includes mobile web
          when platform = 'mob' then 'Mobile/Tablet'
          when platform = 'pc' then 'Desktop/Laptop/Netbook'
          when platform = 'srv' then 'Server-Side App'
          when platform = 'app' then 'General App'
          when platform = 'tv' then 'Connected TV'
          when platform = 'cnsl' then 'Games Console'
          when platform = 'iot' then 'Internet of Things'
          when platform = 'headset' then 'AR/VR Headset' end as platform_name
    from base_query_2 as ev
  )
  select
    *,
      case when platform = 'web' then yauaa__device_class
          when yauaa__device_class = 'Phone' then 'Mobile'
          when yauaa__device_class = 'Tablet' then 'Tablet'
          else platform_name end as device_category

  from base
  WHERE
  CASE WHEN
    GETVARIABLE('ua_bot_filter') = True THEN
      useragent not similar to '.*(bot|crawl|slurp|spider|archiv|spinn|sniff|seo|audit|survey|pingdom|worm|capture|(browser|screen)shots|analyz|index|thumb|check|facebook|PingdomBot|PhantomJS|YandexBot|Twitterbot|a_archiver|facebookexternalhit|Bingbot|BingPreview|Googlebot|Baiduspider|360(Spider|User-agent)|semalt).*'          
    ELSE
      1=1
  END

  -- END: Unified events

  -- START: Screen / page metrics

 DROP VIEW IF EXISTS unified_screen_summary_metrics;
DROP VIEW IF EXISTS unified_pv_engaged_time; -- drop if required

CREATE VIEW unified_screen_summary_metrics AS (
  with prep as (
  select
    ev.view_id
    , ev.session_identifier
    , round(cast(max(ev.screen_summary__foreground_sec) as float), 2) as foreground_sec
    , round(cast(max(ev.screen_summary__background_sec) as float), 2) as background_sec
    , max(ev.screen_summary__last_item_index) as last_item_index
    , max(ev.screen_summary__items_count)::int as items_count
    , min(ev.screen_summary__min_x_offset) as min_x_offset
    , min(ev.screen_summary__min_y_offset) as min_y_offset
    , max(ev.screen_summary__max_x_offset) as max_x_offset
    , max(ev.screen_summary__max_y_offset) as max_y_offset
    , max(ev.screen_summary__content_width)::int as content_width
    , max(ev.screen_summary__content_height)::int as content_height
  from unified_events as ev
  where ev.view_id is not null
    and ev.platform <> 'web'
    and ev.event_name in ('screen_end', 'application_background', 'application_foreground')
  group by 1, 2
)
select *
  , case
    when max_x_offset is not null and content_width is not null and content_width > 0 then
      cast(round(100.0 * cast(max_x_offset as float) / cast(content_width as float)) as float)
    else null
  end as horizontal_percentage_scrolled
  , case
    when max_y_offset is not null and content_height is not null and content_height > 0 then
      cast(round(100.0 * cast(max_y_offset as float) / cast(content_height as float)) as float)
    else null
  end as vertical_percentage_scrolled
  , case
    when last_item_index is not null and items_count is not null and items_count > 0 then
      cast(round(100.0 * (cast(last_item_index as float) + 1) / cast(items_count as float)) as float)
    else null
  end as list_items_percentage_scrolled
from prep
);

CREATE VIEW unified_pv_engaged_time AS
SELECT 
  ev.view_id,
  ev.session_identifier,
  MAX(ev.derived_tstamp) AS end_tstamp,
  (GETVARIABLE('heartbeat') * (COUNT(DISTINCT FLOOR(EXTRACT(EPOCH FROM ev.dvce_created_tstamp) / GETVARIABLE('heartbeat'))) - 1)) + GETVARIABLE('min_visit_length') AS engaged_time_in_s,
  CAST(NULL AS FLOAT) AS absolute_time_in_s
FROM unified_events AS ev
WHERE ev.event_name = 'page_ping'
AND ev.view_id IS NOT NULL
GROUP BY ev.view_id, ev.session_identifier
UNION ALL -- screen summary metrics (if they exist!)
SELECT
  t.view_id,
  t.session_identifier,
  NULL::timestamp AS end_tstamp,
  t.foreground_sec as engaged_time_in_s,
  t.foreground_sec + coalesce(t.background_sec, 0) AS absolute_time_in_s
FROM
  unified_screen_summary_metrics t;

DROP VIEW IF EXISTS unified_pv_scroll_depth;
create view unified_pv_scroll_depth AS
with prep as (
  select
    ev.view_id,
    ev.session_identifier,

    max(ev.doc_width) as doc_width,
    max(ev.doc_height) as doc_height,
    max(ev.br_viewwidth) as br_viewwidth,
    max(ev.br_viewheight) as br_viewheight,

    -- coalesce replaces null with 0 (because the page view event does send an offset)
    -- greatest prevents outliers (negative offsets)
    -- least also prevents outliers (offsets greater than the docwidth or docheight)
    least(greatest(min(coalesce(ev.pp_xoffset_min, 0)), 0), max(ev.doc_width)) as hmin, -- should be zero
    least(greatest(max(coalesce(ev.pp_xoffset_max, 0)), 0), max(ev.doc_width)) as hmax,
    
    least(greatest(min(coalesce(ev.pp_yoffset_min, 0)), 0), max(ev.doc_height)) as vmin, -- should be zero (edge case: not zero because the pv event is missing)
    least(greatest(max(coalesce(ev.pp_yoffset_max, 0)), 0), max(ev.doc_height)) as vmax

  from unified_events as ev

  where ev.event_name in ('page_view', 'page_ping')
    and ev.view_id is not null
    and ev.doc_height > 0 -- exclude problematic (but rare) edge case
    and ev.doc_width > 0 -- exclude problematic (but rare) edge case

  group by 1, 2
)

select
  view_id,
  session_identifier,
  doc_width,
  doc_height,
  br_viewwidth,
  br_viewheight,
  hmin,
  hmax,
  vmin,
  vmax,
  cast(round(100*(greatest(hmin, 0)/cast(doc_width as FLOAT))) as FLOAT) as relative_hmin, -- brackets matter: because hmin is of type int, we need to divide before we multiply by 100 or we risk an overflow
  cast(round(100*(least(hmax + br_viewwidth, doc_width)/cast(doc_width as FLOAT))) as FLOAT) as relative_hmax,
  cast(round(100*(greatest(vmin, 0)/cast(doc_height as FLOAT))) as FLOAT) as relative_vmin,
  cast(round(100*(least(vmax + br_viewheight, doc_height)/cast(doc_height as FLOAT))) as FLOAT) as relative_vmax, -- not zero when a user hasn't scrolled because it includes the non-zero viewheight
  cast(null as INT) as last_list_item_index,
  cast(null as INT) as list_items_count,
  cast(null as INT) as list_items_percentage_scrolled
from prep
-- screen summary stats
union all
select
  t.view_id,
  t.session_identifier,
  t.content_width as doc_width,
  t.content_height as doc_height,
  NULL::int as br_viewwidth,
  NULL::int as br_viewheight,
  t.min_x_offset as hmin,
  t.max_x_offset as hmax,
  t.min_y_offset as vmin,
  t.max_y_offset as vmax,
  NULL::float as relative_hmin,
  t.horizontal_percentage_scrolled as relative_hmax,
  NULL::float as relative_vmin,
  t.vertical_percentage_scrolled as relative_vmax,
  t.last_item_index as last_list_item_index,
  t.items_count as list_items_count,
  t.list_items_percentage_scrolled
from unified_screen_summary_metrics as t;

-- END: Screen / page metrics

-- START: Unified views
DROP VIEW IF EXISTS unified_views;
create view unified_views AS
with prep as (
  select
    -- event categorization fields
    ev.event_name,
    ev.user_id,
    ev.user_identifier,
    ev.network_userid,
    -- timestamp fields
    ev.dvce_created_tstamp,
    ev.collector_tstamp,
    ev.derived_tstamp,
    ev.derived_tstamp as start_tstamp,
    -- geo fields
    ev.geo_country,
    ev.geo_region,
    ev.geo_region_name,
    ev.geo_city,
    ev.geo_zipcode,
    ev.geo_latitude,
    ev.geo_longitude,
    ev.geo_timezone,
    ev.user_ipaddress,
    -- device fields
    ev.app_id,
    ev.platform,
    ev.device_identifier,
    ev.device_category,
    ev.device_session_index,
    ev.os_version,
    ev.os_type,
    ev.screen_resolution,
    -- marketing fields
    ev.mkt_medium,
    ev.mkt_source,
    ev.mkt_term,
    ev.mkt_content,
    ev.mkt_campaign,
    ev.mkt_clickid,
    ev.mkt_network,
case
   when lower(trim(
      mkt_source
)) = 'direct' and lower(trim(
      mkt_medium
)) in ('not set', 'none') then 'Direct'
   when lower(trim(   
      mkt_medium
)) like '%cross-network%' then 'Cross-network'
   when lower(trim(
      mkt_medium)) SIMILAR TO '^(.*cp.*|ppc|retargeting|paid.*)$' then
      case
         when upper(NULL) = 'SOURCE_CATEGORY_SHOPPING'
            or lower(trim(mkt_campaign)) SIMILAR TO '^(.*(([^a-df-z]|^)shop|shopping).*)$' then 'Paid Shopping'
         when upper(NULL) = 'SOURCE_CATEGORY_SEARCH' then 'Paid Search'
         when upper(NULL) = 'SOURCE_CATEGORY_SOCIAL' then 'Paid Social'
         when upper(NULL) = 'SOURCE_CATEGORY_VIDEO' then 'Paid Video'
         else 'Paid Other'
      end
   when lower(trim(mkt_medium
)) in ('display', 'banner', 'expandable', 'intersitial', 'cpm') then 'Display'
   when upper(NULL) = 'SOURCE_CATEGORY_SHOPPING'
      or lower(trim(mkt_campaign)) SIMILAR TO '^(.*(([^a-df-z]|^)shop|shopping).*)$' then 'Organic Shopping'
   when upper(NULL) = 'SOURCE_CATEGORY_SOCIAL' or lower(trim(
      mkt_medium
)) in ('social', 'social-network', 'sm', 'social network', 'social media') then 'Organic Social'
   when upper(NULL) = 'SOURCE_CATEGORY_VIDEO'
      or lower(trim(mkt_medium)) SIMILAR TO '^(.*video.*)$' then 'Organic Video'
   when upper(NULL) = 'SOURCE_CATEGORY_SEARCH' or lower(trim(
      mkt_medium
)) = 'organic' then 'Organic Search'
   when lower(trim(
      mkt_medium
)) in ('referral', 'app', 'link') then 'Referral'
   when lower(trim(
      mkt_source
)) in ('email', 'e-mail', 'e_mail', 'e mail') or lower(trim(
      mkt_medium
)) in ('email', 'e-mail', 'e_mail', 'e mail') then 'Email'
   when lower(trim(
      mkt_medium
)) = 'affiliate' then 'Affiliates'
   when lower(trim(
      mkt_medium
)) = 'audio' then 'Audio'
   when lower(trim(
      mkt_source
)) = 'sms' or lower(trim(
      mkt_medium
)) = 'sms' then 'SMS'
   when lower(trim(
      mkt_medium
)) like '%push' or lower(trim(mkt_medium)) SIMILAR TO '.*(mobile|notification).*' or lower(trim(
      mkt_source
)) = 'firebase' then 'Mobile Push Notifications'
   else 'Unassigned'
end
 as default_channel_group,
    -- webpage / referer / browser fields
    ev.page_url,
    ev.page_referrer,
    ev.refr_medium,
    ev.refr_source,
    ev.refr_term,
    ev.useragent
    , view_id
    , session_identifier
    , event_id
      , ev.br_lang
      , ev.br_viewwidth
      , ev.br_viewheight
      , ev.br_renderengine
      , ev.doc_width
      , ev.doc_height
      , ev.page_title
      , ev.page_urlscheme
      , ev.page_urlhost
      , ev.page_urlpath
      , ev.page_urlquery
      , ev.page_urlfragment
      , ev.refr_urlscheme
      , ev.refr_urlhost
      , ev.refr_urlpath
      , ev.refr_urlquery
      , ev.refr_urlfragment
      , ev.os_timezone
      , 'other' as content_group
      , coalesce(cast(ev.browser__color_depth as TEXT),null) as br_colordepth
  , ev.session__previous_session_id
  , ev.screen_view__name
  , ev.screen_view__previous_id
  , ev.screen_view__previous_name
  , ev.screen_view__previous_type
  , ev.screen_view__transition_type
  , ev.screen_view__type
      -- updated with mapping as part of post hook on derived page_views table
      , cast(ev.user_identifier as TEXT) as stitched_user_id
    , ev.iab__category
    , ev.iab__primary_impact
    , ev.iab__reason
    , ev.iab__spider_or_robot
    , ev.yauaa__device_class
    , ev.yauaa__agent_class
    , ev.yauaa__agent_name
    , ev.yauaa__agent_name_version
    , ev.yauaa__agent_name_version_major
    , ev.yauaa__agent_version
    , ev.yauaa__agent_version_major
    , ev.yauaa__device_brand
    , ev.yauaa__device_name
    , ev.yauaa__device_version
    , ev.yauaa__layout_engine_class
    , ev.yauaa__layout_engine_name
    , ev.yauaa__layout_engine_name_version
    , ev.yauaa__layout_engine_name_version_major
    , ev.yauaa__layout_engine_version
    , ev.yauaa__layout_engine_version_major
    , ev.yauaa__operating_system_class
    , ev.yauaa__operating_system_name
    , ev.yauaa__operating_system_name_version
    , ev.yauaa__operating_system_version
      , ev.ua__useragent_family
      , ev.ua__useragent_major
      , ev.ua__useragent_minor
      , ev.ua__useragent_patch
      , ev.ua__useragent_version
      , ev.ua__os_family
      , ev.ua__os_major
      , ev.ua__os_minor
      , ev.ua__os_patch
      , ev.ua__os_patch_minor
      , ev.ua__os_version
      , ev.ua__device_family
  , ev.app__build
  , ev.app__version
    , ev.geo__latitude
    , ev.geo__longitude
    , ev.geo__latitude_longitude_accuracy
    , ev.geo__altitude
    , ev.geo__altitude_accuracy
    , ev.geo__bearing
    , ev.geo__speed
      , ev.screen__id
      , ev.screen__name
      , ev.screen__activity
      , ev.screen__fragment
      , ev.screen__top_view_controller
      , ev.screen__type
      , ev.screen__view_controller
    , ev.mobile__device_manufacturer
    , ev.mobile__device_model
    , ev.mobile__os_type
    , ev.mobile__os_version
    , ev.mobile__android_idfa
    , ev.mobile__apple_idfa
    , ev.mobile__apple_idfv
    , ev.mobile__carrier
    , ev.mobile__open_idfa
    , ev.mobile__network_technology
    , ev.mobile__network_type
    , ev.mobile__physical_memory
    , ev.mobile__system_available_memory
    , ev.mobile__app_available_memory
    , ev.mobile__battery_level
    , ev.mobile__battery_state
    , ev.mobile__low_power_mode
    , ev.mobile__available_storage
    , ev.mobile__total_storage
    , ev.mobile__is_portrait
    , ev.mobile__resolution
    , ev.mobile__scale
    , ev.mobile__language
    , ev.mobile__app_set_id
    , ev.mobile__app_set_id_scope
      ,ev.v_collector
      ,event_id as event_id2

    from unified_events as ev

    -- removes ga4 source categories
    where ev.event_name in ('page_view', 'screen_view')
    and ev.view_id is not null
    and coalesce(iab__spider_or_robot, False ) = False
      qualify row_number() over (partition by ev.view_id order by ev.derived_tstamp, ev.dvce_created_tstamp) = 1
    
),
view_aggs as (
  select 
    view_id
    , session_identifier
      , 
    from unified_events as ev
    where 1=1 
    and coalesce(iab__spider_or_robot, False ) = False
    group by 1, 2
),
view_events as (
  select
    p.*
    , row_number() over (partition by p.session_identifier order by p.derived_tstamp, p.dvce_created_tstamp, p.event_id) AS view_in_session_index
    , coalesce(t.end_tstamp, p.derived_tstamp) as end_tstamp -- only page views with pings will have a row in table t
      , coalesce(t.engaged_time_in_s, 0) as engaged_time_in_s -- where there are no pings, engaged time is 0.
      , coalesce(
        t.absolute_time_in_s,
        datediff(
        'second',
        p.derived_tstamp,
        coalesce(t.end_tstamp, p.derived_tstamp)
        )
      ) as absolute_time_in_s
      , sd.hmax as horizontal_pixels_scrolled
      , sd.vmax as vertical_pixels_scrolled
      , sd.relative_hmax as horizontal_percentage_scrolled
      , sd.relative_vmax as vertical_percentage_scrolled
    , 
    current_timestamp as model_tstamp
  from prep p
  left join unified_pv_engaged_time t
  on p.view_id = t.view_id and p.session_identifier = t.session_identifier
  left join unified_pv_scroll_depth sd
  on p.view_id = sd.view_id and p.session_identifier = sd.session_identifier
)
select
    -- event categorization fields
    pve.view_id
    , pve.event_name
    , pve.event_id
    , pve.session_identifier
    , pve.view_in_session_index
    , max(pve.view_in_session_index) over (partition by pve.session_identifier) as views_in_session
    -- user id fields
    , pve.user_id
    , pve.user_identifier
    , pve.stitched_user_id
    , pve.network_userid
    -- timestamp fields
    , pve.dvce_created_tstamp
    , pve.collector_tstamp
    , pve.derived_tstamp
    , pve.derived_tstamp as start_tstamp
    , pve.end_tstamp -- only page views with pings will have a row in table t
    , pve.model_tstamp
    -- device fields
    , pve.app_id
    , pve.platform
    , pve.device_identifier
    , pve.device_category
    , pve.device_session_index
    , pve.os_version
    , pve.os_type
    , pve.mobile__device_manufacturer
    , pve.mobile__device_model
    , pve.mobile__os_type
    , pve.mobile__os_version
    , pve.mobile__android_idfa
    , pve.mobile__apple_idfa
    , pve.mobile__apple_idfv
    , pve.mobile__carrier
    , pve.mobile__open_idfa
    , pve.mobile__network_technology
    , pve.mobile__network_type
    , pve.mobile__physical_memory
    , pve.mobile__system_available_memory
    , pve.mobile__app_available_memory
    , pve.mobile__battery_level
    , pve.mobile__battery_state
    , pve.mobile__low_power_mode
    , pve.mobile__available_storage
    , pve.mobile__total_storage
    , pve.mobile__is_portrait
    , pve.mobile__resolution
    , pve.mobile__scale
    , pve.mobile__language
    , pve.mobile__app_set_id
    , pve.mobile__app_set_id_scope
    , pve.screen_resolution
    -- geo fields
    , pve.geo_country
    , pve.geo_region
    , pve.geo_region_name
    , pve.geo_city
    , pve.geo_zipcode
    , pve.geo_latitude
    , pve.geo_longitude
    , pve.geo_timezone
    , pve.user_ipaddress
    -- engagement fields
      , pve.engaged_time_in_s -- where there are no pings, engaged time is 0.
      , pve.absolute_time_in_s
      , pve.horizontal_pixels_scrolled
      , pve.vertical_pixels_scrolled
      , pve.horizontal_percentage_scrolled
      , pve.vertical_percentage_scrolled
    -- marketing fields
    , pve.mkt_medium
    , pve.mkt_source
    , pve.mkt_term
    , pve.mkt_content
    , pve.mkt_campaign
    , pve.mkt_clickid
    , pve.mkt_network
    , pve.default_channel_group
    -- webpage / referer / browser fields
    , pve.page_url
    , pve.page_referrer
    , pve.refr_medium
    , pve.refr_source
    , pve.refr_term
      , br_colordepth
      , pve.br_lang
      , pve.br_viewwidth
      , pve.br_viewheight
      , pve.br_renderengine
      , pve.doc_width
      , pve.doc_height
      , pve.page_title
      , pve.page_urlscheme
      , pve.page_urlhost
      , pve.page_urlpath
      , pve.page_urlquery
      , pve.page_urlfragment
      , pve.refr_urlscheme
      , pve.refr_urlhost
      , pve.refr_urlpath
      , pve.refr_urlquery
      , pve.refr_urlfragment
      , pve.os_timezone
      , content_group
    -- iab enrichment fields
    , pve.iab__category
    , pve.iab__primary_impact
    , pve.iab__reason
    , pve.iab__spider_or_robot
    -- yauaa enrichment fields
    , pve.yauaa__device_class
    , pve.yauaa__agent_class
    , pve.yauaa__agent_name
    , pve.yauaa__agent_name_version
    , pve.yauaa__agent_name_version_major
    , pve.yauaa__agent_version
    , pve.yauaa__agent_version_major
    , pve.yauaa__device_brand
    , pve.yauaa__device_name
    , pve.yauaa__device_version
    , pve.yauaa__layout_engine_class
    , pve.yauaa__layout_engine_name
    , pve.yauaa__layout_engine_name_version
    , pve.yauaa__layout_engine_name_version_major
    , pve.yauaa__layout_engine_version
    , pve.yauaa__layout_engine_version_major
    , pve.yauaa__operating_system_class
    , pve.yauaa__operating_system_name
    , pve.yauaa__operating_system_name_version
    , pve.yauaa__operating_system_version
    -- ua parser enrichment fields
      , pve.ua__useragent_family
      , pve.ua__useragent_major
      , pve.ua__useragent_minor
      , pve.ua__useragent_patch
      , pve.ua__useragent_version
      , pve.ua__os_family
      , pve.ua__os_major
      , pve.ua__os_minor
      , pve.ua__os_patch
      , pve.ua__os_patch_minor
      , pve.ua__os_version
      , pve.ua__device_family
    -- mobile only
  , pve.session__previous_session_id
  , pve.screen_view__name
  , pve.screen_view__previous_id
  , pve.screen_view__previous_name
  , pve.screen_view__previous_type
  , pve.screen_view__transition_type
  , pve.screen_view__type
  , pve.app__build
  , pve.app__version
    , pve.geo__latitude
    , pve.geo__longitude
    , pve.geo__latitude_longitude_accuracy
    , pve.geo__altitude
    , pve.geo__altitude_accuracy
    , pve.geo__bearing
    , pve.geo__speed
      , pve.screen__fragment
      , pve.screen__top_view_controller
      , pve.screen__view_controller
    , pve.useragent
        , pve.v_collector
from view_events pve
  left join view_aggs a on pve.session_identifier = a.session_identifier and pve.view_id = a.view_id;

-- END: Unified views

-- START: Unified sessions
-- unified sessions
DROP VIEW IF EXISTS unified_sessions;
CREATE VIEW unified_sessions AS
WITH session_firsts as (
    select
    -- event categorization fields
    ev.event_name,
    ev.user_id,
    ev.user_identifier,
    ev.network_userid,
    -- timestamp fields
    ev.dvce_created_tstamp,
    ev.collector_tstamp,
    ev.derived_tstamp,
    ev.derived_tstamp as start_tstamp,
    -- geo fields
    ev.geo_country,
    ev.geo_region,
    ev.geo_region_name,
    ev.geo_city,
    ev.geo_zipcode,
    ev.geo_latitude,
    ev.geo_longitude,
    ev.geo_timezone,
    ev.user_ipaddress,
    -- device fields
    ev.app_id,
    ev.platform,
    ev.device_identifier,
    ev.device_category,
    ev.device_session_index,
    ev.os_version,
    ev.os_type,
    ev.screen_resolution,
    -- marketing fields
    ev.mkt_medium,
    ev.mkt_source,
    ev.mkt_term,
    ev.mkt_content,
    ev.mkt_campaign,
    ev.mkt_clickid,
    ev.mkt_network,
NULL as default_channel_group,

    -- webpage / referer / browser fields
    ev.page_url,
    ev.page_referrer,
    ev.refr_medium,
    ev.refr_source,
    ev.refr_term,
    ev.useragent
        , session_identifier
      , ev.br_lang
      , ev.br_viewwidth
      , ev.br_viewheight
      , ev.br_renderengine
      , ev.doc_width
      , ev.doc_height
      , ev.page_title
      , ev.page_urlscheme
      , ev.page_urlhost
      , ev.page_urlpath
      , ev.page_urlquery
      , ev.page_urlfragment
      , ev.refr_urlscheme
      , ev.refr_urlhost
      , ev.refr_urlpath
      , ev.refr_urlquery
      , ev.refr_urlfragment
      , ev.os_timezone
  , ev.session__previous_session_id
  , ev.screen_view__name
  , ev.screen_view__previous_id
  , ev.screen_view__previous_name
  , ev.screen_view__previous_type
  , ev.screen_view__transition_type
  , ev.screen_view__type
          -- updated with mapping as part of post hook on derived sessions table
          , cast(user_identifier as 
    TEXT
) as stitched_user_id
    , ev.iab__category
    , ev.iab__primary_impact
    , ev.iab__reason
    , ev.iab__spider_or_robot

    , ev.yauaa__device_class
    , ev.yauaa__agent_class
    , ev.yauaa__agent_name
    , ev.yauaa__agent_name_version
    , ev.yauaa__agent_name_version_major
    , ev.yauaa__agent_version
    , ev.yauaa__agent_version_major
    , ev.yauaa__device_brand
    , ev.yauaa__device_name
    , ev.yauaa__device_version
    , ev.yauaa__layout_engine_class
    , ev.yauaa__layout_engine_name
    , ev.yauaa__layout_engine_name_version
    , ev.yauaa__layout_engine_name_version_major
    , ev.yauaa__layout_engine_version
    , ev.yauaa__layout_engine_version_major
    , ev.yauaa__operating_system_class
    , ev.yauaa__operating_system_name
    , ev.yauaa__operating_system_name_version
    , ev.yauaa__operating_system_version

      , ev.ua__useragent_family
      , ev.ua__useragent_major
      , ev.ua__useragent_minor
      , ev.ua__useragent_patch
      , ev.ua__useragent_version
      , ev.ua__os_family
      , ev.ua__os_major
      , ev.ua__os_minor
      , ev.ua__os_patch
      , ev.ua__os_patch_minor
      , ev.ua__os_version
      , ev.ua__device_family

  , NULL AS app__build
  , NULL AS app__version

    , ev.geo__latitude
    , ev.geo__longitude
    , ev.geo__latitude_longitude_accuracy
    , ev.geo__altitude
    , ev.geo__altitude_accuracy
    , ev.geo__bearing
    , ev.geo__speed
    , g.name as geo_country_name 
    , g.region as geo_continent
    , l.name as br_lang_name

      , ev.screen__id
      , ev.screen__name
      , ev.screen__activity
      , ev.screen__fragment
      , ev.screen__top_view_controller
      , ev.screen__type
      , ev.screen__view_controller

    , ev.mobile__device_manufacturer
    , ev.mobile__device_model
    , ev.mobile__os_type
    , ev.mobile__os_version
    , ev.mobile__android_idfa
    , ev.mobile__apple_idfa
    , ev.mobile__apple_idfv
    , ev.mobile__carrier
    , ev.mobile__open_idfa
    , ev.mobile__network_technology
    , ev.mobile__network_type
    , ev.mobile__physical_memory
    , ev.mobile__system_available_memory
    , ev.mobile__app_available_memory
    , ev.mobile__battery_level
    , ev.mobile__battery_state
    , ev.mobile__low_power_mode
    , ev.mobile__available_storage
    , ev.mobile__total_storage
    , ev.mobile__is_portrait
    , ev.mobile__resolution
    , ev.mobile__scale
    , ev.mobile__language
    , ev.mobile__app_set_id
    , ev.mobile__app_set_id_scope
        , 
  regexp_extract(page_urlquery, 'utm_source_platform=([^?&#]*)', 1)
 as mkt_source_platform
            ,ev.event_id

    from unified_events ev
    LEFT JOIN
    unified_dim_rfc_5646_language_mapping l ON lower(ev.br_lang) = lower(l.lang_tag)
    LEFT JOIN
    unified_dim_geo_country_mapping g ON lower(ev.geo_country) = lower(g.alpha_2)
    -- ga seed data is excluded
  
    -- no join to GA seed data, ISO data
    where event_name in ('page_ping', 'page_view', 'screen_view')
    and view_id is not null
    and coalesce(iab__spider_or_robot, False ) = False
      qualify row_number() over (partition by session_identifier order by derived_tstamp) = 1
    
),
session_lasts as (
    select
      ev.event_name as last_event_name,
      ev.geo_country as last_geo_country,
      ev.geo_city as last_geo_city,
      ev.geo_region_name as last_geo_region_name,
      g.name as last_geo_country_name,
      g.region as last_geo_continent,
      ev.page_url as last_page_url,
        ev.page_title as last_page_title,
        ev.page_urlscheme as last_page_urlscheme,
        ev.page_urlhost as last_page_urlhost,
        ev.page_urlpath as last_page_urlpath,
        ev.page_urlquery as last_page_urlquery,
        ev.page_urlfragment as last_page_urlfragment,
        br_lang as last_br_lang,
        l.name as last_br_lang_name, -- no support for language name
        ev.screen_view__name as last_screen_view__name,
        ev.screen_view__transition_type as last_screen_view__transition_type,
        ev.screen_view__type as last_screen_view__type,
        session_identifier
    from unified_events ev
      LEFT JOIN
    unified_dim_rfc_5646_language_mapping l ON lower(ev.br_lang) = lower(l.lang_tag)
      LEFT JOIN
    unified_dim_geo_country_mapping g ON lower(ev.geo_country) = lower(g.alpha_2)
    where
        event_name in ('page_view', 'screen_view')
        and view_id is not null
    and coalesce(iab__spider_or_robot, False ) = False
      qualify row_number() over (partition by session_identifier order by derived_tstamp desc) = 1
    
),
session_aggs as (
    select
      session_identifier
      , min(derived_tstamp) as start_tstamp
      , max(derived_tstamp) as end_tstamp
      , count(*) as total_events
      , count(distinct view_id) as views
          , 
      histogram(event_name) AS event_counts
      ,NULL as event_counts_string, -- TODO, consider whether this is needed or not?
     (GETVARIABLE('heartbeat') * (
              -- number of (unqiue in heartbeat increment) pages pings following a page ping (gap of heartbeat)
              count(distinct case when event_name = 'page_ping' and view_id is not null then
                          -- need to get a unique list of floored time PER page view, so create a dummy surrogate key...
                          view_id || cast(floor(epoch(dvce_created_tstamp)/GETVARIABLE('heartbeat')) as TEXT)
                      else null end) - count(distinct case when event_name = 'page_ping' and view_id is not null then view_id else null end)
                            ))  +
                            -- number of page pings following a page view (or no event) (gap of min visit length)
                            (count(distinct case when event_name = 'page_ping' and view_id is not null then view_id else null end) * GETVARIABLE('min_visit_length')) as engaged_time_in_s_web
      , datediff('second', min(derived_tstamp), max(derived_tstamp)) as absolute_time_in_s
        -- TODO, count(distinct case when event_name = 'application_error' then 1 end) as app_errors
        -- , count(distinct case when app_error__is_fatal then event_id end) as fatal_app_errors
        -- , count(distinct screen_view__name) as screen_names_viewed
    from unified_events
    where 1 = 1
    and coalesce(iab__spider_or_robot, False ) = False
    group by session_identifier
),
session_aggs_with_engaged_time as (
    select a.*
      , a.engaged_time_in_s_web as engaged_time_in_s
    from session_aggs a
),
iso_639_3_deduped AS (
  SELECT
    *,
    row_number() over (partition by iso_639_3_code ORDER BY name) as row_num
  FROM
    unified_dim_iso_639_3
),
session_convs as (
    select
        session_identifier
        -- TODO: consider removing these examples?
,COUNT(CASE WHEN event_name = 'page_view' THEN 1 ELSE null END) AS cv_view_page_volume
,SUM(CASE WHEN event_name = 'page_view' THEN coalesce(tr_total_base, 0.5) ELSE 0 END) AS cv_view_page_total
,MIN(CASE WHEN event_name = 'page_view' THEN derived_tstamp ELSE null END) AS cv_view_page_first_conversion
,CAST(MAX(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END) AS BOOLEAN) AS cv_view_page_converted
          from unified_events
          where 1 = 1
    and coalesce(iab__spider_or_robot, False ) = False
        group by session_identifier
)
select
  -- event categorization fields
  f.event_name as first_event_name
  , l.last_event_name
  , f.session_identifier
    -- , f.session__previous_session_id
  -- user id fields
  , f.user_id
  , f.user_identifier
  , f.stitched_user_id
  , f.network_userid
  -- timestamp fields
  -- when the session starts with a ping we need to add the min visit length to get when the session actually started
  , case when f.event_name = 'page_ping' then 
    a.start_tstamp - INTERVAL (GETVARIABLE('min_visit_length')) SECOND
 else a.start_tstamp end as start_tstamp
  , a.end_tstamp -- only page views with pings will have a row in table t
  , 
  current_timestamp as model_tstamp
  -- device fields
  , f.app_id
  , f.platform
  , f.device_identifier
  , f.device_category
  , f.device_session_index
  , f.os_version
  , f.os_type
    , f.os_timezone
  , f.screen_resolution

    , f.mobile__device_manufacturer
    , f.mobile__device_model
    , f.mobile__os_type
    , f.mobile__os_version
    , f.mobile__android_idfa
    , f.mobile__apple_idfa
    , f.mobile__apple_idfv
    , f.mobile__carrier
    , f.mobile__open_idfa
    , f.mobile__network_technology
    , f.mobile__network_type
    , f.mobile__physical_memory
    , f.mobile__system_available_memory
    , f.mobile__app_available_memory
    , f.mobile__battery_level
    , f.mobile__battery_state
    , f.mobile__low_power_mode
    , f.mobile__available_storage
    , f.mobile__total_storage
    , f.mobile__is_portrait
    , f.mobile__resolution
    , f.mobile__scale
    , f.mobile__language
    , f.mobile__app_set_id
    , f.mobile__app_set_id_scope
    , coalesce(iso_639_2t_2_char.name, iso_639_2t_3_char.name, iso_639_3.name, f.mobile__language) as mobile_language_name
  
  -- geo fields
  , f.geo_country as first_geo_country
  , f.geo_region_name as first_geo_region_name
  , f.geo_city as first_geo_city
  , f.geo_country_name as first_geo_country_name
  , f.geo_continent as first_geo_continent

  , case when l.last_geo_country is null then coalesce(l.last_geo_country, f.geo_country) else l.last_geo_country end as last_geo_country
  , case when l.last_geo_country is null then coalesce(l.last_geo_region_name, f.geo_region_name) else l.last_geo_region_name end as last_geo_region_name
  , case when l.last_geo_country is null then coalesce(l.last_geo_city, f.geo_city) else l.last_geo_city end as last_geo_city
  , case when l.last_geo_country is null then coalesce(l.last_geo_country_name,f.geo_country_name) else l.last_geo_country_name end as last_geo_country_name
  , case when l.last_geo_country is null then coalesce(l.last_geo_continent, f.geo_continent) else l.last_geo_continent end as last_geo_continent

  , f.geo_zipcode
  , f.geo_latitude
  , f.geo_longitude
  , f.geo_timezone
  , f.user_ipaddress

  -- engagement fields
  , a.views
  , a.event_counts
  , JSON(a.event_counts) AS event_counts_string
  , a.total_events
  , coalesce(
    case when 
    views >= 2
      or engaged_time_in_s / 10 >= 2
        or cv_view_page_converted THEN true end
, false) as is_engaged
  -- when the session starts with a ping we need to add the min visit length to get when the session actually started
    , a.engaged_time_in_s
  , a.absolute_time_in_s + case when f.event_name = 'page_ping' then GETVARIABLE('min_visit_length') else 0 end as absolute_time_in_s
    -- TODO, a.screen_names_viewed
  -- marketing fields
  , f.mkt_medium
  , f.mkt_source
  , f.mkt_term
  , f.mkt_content
  , f.mkt_campaign
  , f.mkt_clickid
  , f.mkt_network
  , f.default_channel_group
  , mkt_source_platform

  -- webpage / referrer / browser fields
  , f.page_url as first_page_url
  , case when l.last_page_url is null then coalesce(l.last_page_url, f.page_url) else l.last_page_url end as last_page_url
  , f.page_referrer
  , f.refr_medium
  , f.refr_source
  , f.refr_term
    , f.page_title as first_page_title
    , f.page_urlscheme as first_page_urlscheme
    , f.page_urlhost as first_page_urlhost
    , f.page_urlpath as first_page_urlpath
    , f.page_urlquery as first_page_urlquery
    , f.page_urlfragment as first_page_urlfragment
    -- only take the first value when the last is genuinely missing (base on url as has to always be populated)
    , case when l.last_page_url is null then coalesce(l.last_page_title, f.page_title) else l.last_page_title end as last_page_title
    , case when l.last_page_url is null then coalesce(l.last_page_urlscheme, f.page_urlscheme) else l.last_page_urlscheme end as last_page_urlscheme
    , case when l.last_page_url is null then coalesce(l.last_page_urlhost, f.page_urlhost) else l.last_page_urlhost end as last_page_urlhost
    , case when l.last_page_url is null then coalesce(l.last_page_urlpath, f.page_urlpath) else l.last_page_urlpath end as last_page_urlpath
    , case when l.last_page_url is null then coalesce(l.last_page_urlquery, f.page_urlquery) else l.last_page_urlquery end as last_page_urlquery
    , case when l.last_page_url is null then coalesce(l.last_page_urlfragment, f.page_urlfragment) else l.last_page_urlfragment end as last_page_urlfragment
    , f.refr_urlscheme
    , f.refr_urlhost
    , f.refr_urlpath
    , f.refr_urlquery
    , f.refr_urlfragment
    , f.br_renderengine
    , f.br_lang as first_br_lang
    , f.br_lang_name AS first_br_lang_name
    , case when l.last_br_lang is null then coalesce(l.last_br_lang, f.br_lang) else l.last_br_lang end as last_br_lang
    , case when l.last_br_lang is null then coalesce(l.last_br_lang_name, f.br_lang_name) else l.last_br_lang_name end as last_br_lang_name

  
  -- iab enrichment fields
    , f.iab__category
    , f.iab__primary_impact
    , f.iab__reason
    , f.iab__spider_or_robot

  -- yauaa enrichment fields
    , f.yauaa__device_class
    , f.yauaa__agent_class
    , f.yauaa__agent_name
    , f.yauaa__agent_name_version
    , f.yauaa__agent_name_version_major
    , f.yauaa__agent_version
    , f.yauaa__agent_version_major
    , f.yauaa__device_brand
    , f.yauaa__device_name
    , f.yauaa__device_version
    , f.yauaa__layout_engine_class
    , f.yauaa__layout_engine_name
    , f.yauaa__layout_engine_name_version
    , f.yauaa__layout_engine_name_version_major
    , f.yauaa__layout_engine_version
    , f.yauaa__layout_engine_version_major
    , f.yauaa__operating_system_class
    , f.yauaa__operating_system_name
    , f.yauaa__operating_system_name_version
    , f.yauaa__operating_system_version

  -- -- ua parser enrichment fields
      , f.ua__useragent_family
      , f.ua__useragent_major
      , f.ua__useragent_minor
      , f.ua__useragent_patch
      , f.ua__useragent_version
      , f.ua__os_family
      , f.ua__os_major
      , f.ua__os_minor
      , f.ua__os_patch
      , f.ua__os_patch_minor
      , f.ua__os_version
      , f.ua__device_family

  -- mobile only  
    , f.screen_view__name as first_screen_view__name
    , f.screen_view__type as first_screen_view__type
    , case when l.last_screen_view__name is null then coalesce(l.last_screen_view__name, f.screen_view__name) else l.last_screen_view__name end as last_screen_view__name
    , case when l.last_screen_view__transition_type is null then coalesce(l.last_screen_view__transition_type, f.screen_view__transition_type) else l.last_screen_view__transition_type end as last_screen_view__transition_type
    , case when l.last_screen_view__type is null then coalesce(l.last_screen_view__type, f.screen_view__type) else l.last_screen_view__type end as last_screen_view__type
    , f.screen_view__previous_id
    , f.screen_view__previous_name
    , f.screen_view__previous_type

    , f.geo__latitude as first_geo__latitude 
    , f.geo__longitude as first_geo__longitude 
    , f.geo__latitude_longitude_accuracy as first_geo__latitude_longitude_accuracy 
    , f.geo__altitude as first_geo__altitude 
    , f.geo__altitude_accuracy as first_geo__altitude_accuracy 
    , f.geo__bearing as first_geo__bearing 
    , f.geo__speed as first_geo__speed 

    , f.screen__fragment
    , f.screen__top_view_controller
    , f.screen__view_controller  
  , f.useragent
  -- no support for passthrough fields
          , f.event_id
 
from session_firsts f

left join session_lasts l
on f.session_identifier = l.session_identifier
left join session_aggs_with_engaged_time a
on f.session_identifier = a.session_identifier
left join session_convs d on f.session_identifier = d.session_identifier
-- if the language uses a two letter code we can match on that  
left join unified_dim_iso_639_2t iso_639_2t_2_char on lower(f.mobile__language) = lower(iso_639_2t_2_char.iso_639_1_code)
-- if the language uses a three letter code we can match on that
left join unified_dim_iso_639_2t iso_639_2t_3_char on lower(f.mobile__language) = lower(iso_639_2t_3_char.iso_639_2t_code)
  -- A fallback to the three letter code, with a more complete list, we first try to join on the other dataset the three letter code
  -- in order to get a language name that will match the mapping of the two letter code
  left join iso_639_3_deduped iso_639_3 on lower(f.mobile__language) = lower(iso_639_3.iso_639_3_code)
    and iso_639_3.row_num = 1

-- END: Unified sessions

-- START: Unified users sessions

DROP VIEW IF EXISTS unified_users_sessions;
create view unified_users_sessions AS
select
  a.*,
  min(a.start_tstamp) over(partition by a.user_identifier) as user_start_tstamp,
  max(a.end_tstamp) over(partition by a.user_identifier) as user_end_tstamp,
  max(case when platform = 'web' then true else false end) over(partition by user_identifier) as on_web,
  max(case when platform <> 'web' then true else false end) over(partition by user_identifier) as on_mobile
from unified_sessions a;

-- END: Unified users sessions

-- START: User aggs

DROP VIEW IF EXISTS unified_users_aggs;
create view if not exists unified_users_aggs AS
select
  user_identifier
  -- time
  , user_start_tstamp as start_tstamp
  , user_end_tstamp as end_tstamp
  -- first/last session. Max to resolve edge case with multiple sessions with the same start/end tstamp
  , max(case when start_tstamp = user_start_tstamp then session_identifier end) as first_session_identifier
  , max(case when end_tstamp = user_end_tstamp then session_identifier end) as last_session_identifier
  -- engagement
  , sum(views) as views
  , count(distinct session_identifier) as sessions
  , count(distinct date_trunc('day', start_tstamp)) as active_days
    , sum(engaged_time_in_s) as engaged_time_in_s
  , sum(absolute_time_in_s) as absolute_time_in_s
from unified_users_sessions
group by 1,2,3;

-- END: User aggs

-- START: User lasts

-- user lasts
DROP VIEW IF EXISTS unified_users_lasts;
create view unified_users_lasts AS
select
  a.user_identifier
  , a.platform as last_platform
  , os_type as last_os_type
  , os_version as last_os_version
  , screen_resolution as last_screen_resolution
  , a.last_geo_country
  , a.last_geo_country_name
  , a.last_geo_continent
  , a.last_geo_city
  , a.last_geo_region_name
  , a.last_page_url
    , a.last_page_title
    , a.last_page_urlscheme
    , a.last_page_urlhost
    , a.last_page_urlpath
    , a.last_page_urlquery
    , a.last_page_urlfragment

    , a.last_br_lang
    , a.last_br_lang_name
    , a.last_screen_view__name
    , a.last_screen_view__transition_type
    , a.last_screen_view__type
    , a.mobile__carrier as last_mobile__carrier
    , a.mobile__device_manufacturer as last_mobile__device_manufacturer
    , a.mobile__device_model as last_mobile__device_model
    , a.event_id as last_event_id

from unified_users_sessions a

inner join unified_users_aggs b
on a.session_identifier = b.last_session_identifier;

-- END: User lasts

-- START: Unified users

drop view if exists unified_users;
create view unified_users AS select
  -- user fields
  a.user_id
  , a.user_identifier
  , a.network_userid
    , cast(a.user_identifier as TEXT) as stitched_user_id
  -- timestamp fields
  , b.start_tstamp
  , b.end_tstamp
  , 
  current_timestamp as model_tstamp
  -- device fields
  , a.platform as first_platform
  , c.last_platform
  , cast(a.on_web as BOOLEAN) as on_web
  , cast(a.on_mobile as BOOLEAN) as on_mobile
  , c.last_screen_resolution
  , c.last_os_type
  , c.last_os_version
    , a.mobile__device_manufacturer as first_mobile__device_manufacturer
    , a.mobile__device_model as first_mobile__device_model
    , a.mobile__carrier as first_mobile__carrier
    , c.last_mobile__device_manufacturer
    , c.last_mobile__device_model
    , c.last_mobile__carrier
    , a.mobile__os_type
    , a.mobile__os_version
    , a.mobile__android_idfa
    , a.mobile__apple_idfa
    , a.mobile__apple_idfv
    , a.mobile__open_idfa
    , a.mobile__network_technology
    , a.mobile__network_type
    , a.mobile__physical_memory
    , a.mobile__system_available_memory
    , a.mobile__app_available_memory
    , a.mobile__battery_level
    , a.mobile__battery_state
    , a.mobile__low_power_mode
    , a.mobile__available_storage
    , a.mobile__total_storage
    , a.mobile__is_portrait
    , a.mobile__resolution
    , a.mobile__scale
    , a.mobile__language
    , a.mobile__app_set_id
    , a.mobile__app_set_id_scope
    -- Derivative fields
    , NULL AS mobile_language_name
  -- geo fields
  , a.first_geo_country
  , a.first_geo_country_name
  , a.first_geo_continent
  , a.first_geo_city
  , a.first_geo_region_name
  , c.last_geo_country
  , c.last_geo_country_name
  , c.last_geo_continent
  , c.last_geo_city
  , c.last_geo_region_name
  , a.geo_zipcode
  , a.geo_latitude
  , a.geo_longitude
  , a.geo_timezone
  -- engagement fields
  , b.views
  , b.sessions
  , b.active_days
    , b.engaged_time_in_s
  , b.absolute_time_in_s
    -- , b.screen_names_viewed
  -- webpage / referer / browser fields
  , a.page_referrer
  , a.refr_medium
  , a.refr_source
  , a.refr_term
    , a.first_page_title
    , a.first_page_url
    , a.first_page_urlscheme
    , a.first_page_urlhost
    , a.first_page_urlpath
    , a.first_page_urlquery
    , a.first_page_urlfragment
    , a.first_br_lang
    , a.first_br_lang_name
    , c.last_page_title
    , c.last_page_url
    , c.last_page_urlscheme
    , c.last_page_urlhost
    , c.last_page_urlpath
    , c.last_page_urlquery
    , c.last_page_urlfragment
    , c.last_br_lang
    , c.last_br_lang_name
    , a.refr_urlscheme
    , a.refr_urlhost
    , a.refr_urlpath
    , a.refr_urlquery
    , a.refr_urlfragment
    , a.first_screen_view__name
    , a.first_screen_view__type
    , c.last_screen_view__name
    , c.last_screen_view__transition_type
    , c.last_screen_view__type
  -- marketing fields
  , a.mkt_medium
  , a.mkt_source
  , a.mkt_term
  , a.mkt_content
  , a.mkt_campaign
  , a.mkt_clickid
  , a.mkt_network
  , a.mkt_source_platform
  , a.default_channel_group
    ,a.event_id as first_event_id
    ,c.last_event_id  
  
from unified_users_aggs as b

inner join unified_users_sessions as a
on a.session_identifier = b.first_session_identifier

inner join unified_users_lasts c
on b.user_identifier = c.user_identifier

-- END: Unified users