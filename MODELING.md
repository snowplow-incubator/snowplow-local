## Data modeling

Snowplow Local includes a limited version of the [Snowplow Unified](https://docs.snowplow.io/docs/modeling-your-data/modeling-your-data-with-dbt/dbt-models/dbt-unified-data-model/) dbt models.

The model included in this package aims to closely replicate a subset of functionality featured in this dbt package in an easier to run, local only version that yields the same tables.

This package is designed for local use and development, you should avoid running it in production as it makes specific design decisions optimized towards fast-feedback over performance at scale.

### Running

You can find the raw SQL for creating the tables and seeds in `database/unified.sql`. If you wish to run this logic in a notebook (recommended) you can load these queries automatically into a DuckDB notebook by running `duckdb -ui -init unified_notebook.sql`.


### Supported variables
- app_id
- min_visit_length
- heartbeat_interval
- ua_bot_filter
- enable_* for feature flags


### Differences in behaviour
- Data is materialized into views (rather than tables) so that they are automatically refreshed at query time. This allows you to view the most up-to-date data without manually refreshing the tables or running commands at a slight performance cost. As a result this package does not contain any incrementalization logic that you would normally find in the production package.
- The models do not use dbt, instead opting for SQL directly.
- Turning certain features off (e.g., screen_summary) will result in NULL columns rather than missing columns.
- Variables for turning features on and off are set as SQL variables (rather than dbt variables).
- Pushes optional bot filtering logic (based on useragent) to the events table
- `event_counts` counts all events for a user (within that session)



### Limitations

- The GA (Google Analytics) seed is not loaded so source_category is not yielded.
- Pass through fields (user & session) and custom identifiers are not supported.
- Conversions, consent, core web vitals and app error modules are not currently supported (may be supported in a future version).
- Macros are not overrideable meaning you cannot customize things like channel groupings and categories
- Session and user aggregations are not supported
- You cannot disable `event_counts`