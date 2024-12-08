# Snowplow Local

## Background

Snowplow Local is designed to provide a fast, easy to use local development environment that spins up an entire Snowplow pipeline that more closely resembles a production (AWS) environment by mocking out these services using [Localstack](https://www.localstack.cloud/).

## What can you do with Snowplow Local?

- Develop and test new schemas and enrichments
- Test out new loaders (e.g., Snowflake, BigQuery, Lake Loader)
- View bad, incomplete and good events in an easy-to-use user interface
- Test changes to the pipeline configuration (collector, enrich, etc)
- Stream data to your data warehouse or lake of choice
- Monitor pipeline performance and metrics using Grafana
- Test new or existing versions of the Snowplow pipeline
- Write enriched data to remote destinations (including S3, GCS etc)
- Test and validate Snowbridge configurations

## Licensing

This software is licensed under the Snowplow Limited Use License Agreement. For more information please see the [LICENSE.md](LICENSE.md) file. For a more comprehensive list of Snowplow licensing please see [this document](https://docs.snowplow.io/docs/contributing/copyright-license/#source-available-components).

## Disclaimer

>[!IMPORTANT]
>This is not an officially supported Snowplow product.

## Getting started

1. Make sure you have `docker` and `docker-compose` installed
2. Clone or download this repo
3. `cd snowplow-local`
4. Copy the `.env.example` file to a `.env` file. Read and accept the [license terms](LICENSE.md) by setting the `ACCEPT_LICENSE` variable to true.
5. Run everything with `docker-compose up`
6. Open up a page to fire test events in your [browser](http://localhost:8082) using the Javascript tracker.

## Services

The collector runs on port 8080 and can be accessed at [http://localhost:8080](http://localhost:8080). When configuring a [tracker](https://docs.snowplow.io/docs/collecting-data/collecting-from-own-applications/) you can use this as the collector URL.

A user interface listens to events that have been enriched (good, bad and incomplete) and displays them hosted on a page at [http://localhost:3001](http://localhost:3001).

[Iglu Server](https://docs.snowplow.io/docs/pipeline-components-and-applications/iglu/iglu-repositories/iglu-server/) runs on port 8081 and can be accessed at [http://localhost:8081](http://localhost:8081). This is where you can upload your schemas and validate them. You can also point enrich directly at an existing Iglu repository that contains schemas by updating `iglu-client/resolver.json`.

[Grafana](https://grafana.com) is used for metrics reporting and basic dashboarding and runs on port 3000 and can be accessed at [http://localhost:3000](http://localhost:3000). The default credentials are `admin:admin`. Graphite is used as the default data source so this does not require manual configuration - the collector and [enricher](https://docs.snowplow.io/docs/pipeline-components-and-applications/enrichment-components/monitoring/) will both emit statsd metrics here automatically.

A basic website that can be used to fire test events can be accessed at [http://localhost:8082](http://localhost:8082). This is useful for testing your pipeline and ensuring that events are being collected correctly.

## Differences to a production pipeline

This software is not designed to be run in production or at high volume and is instead designed for a local experience.

Some differences include statsd reporting intervals (shorter period than ordinary) as well as caching settings for Iglu clients in order to more easily allow for patching without needing to clear caches manually or reboot services.

## Configuring loaders

By default good, bad and incomplete events are written to a SQLite database (`database/events.db`) for persistence beyond restarts. This is useful for debugging what events have occurred if you are not loading into a warehouse or lake.

However, if you do want to load to a production target you can also do so.

Loaders are configured using the `--profile` flag. Currently the following loaders are supported:

[ * ] Snowflake streaming loader (`--profile snowflake-loader`)
[ * ] Lake loader (Delta, Hudi & Iceberg) (`--profile lake-loader`)
[ * ] BigQuery streaming loader (`--profile bigquery-loader`)

If you would like to (optionally) run the Snowflake streaming loader as well you will need to run these steps.

1. Configure your Snowflake private key and warehouse details in your `.env` file. You will need a [private key](https://docs.snowflake.com/en/user-guide/key-pair-auth) set up rather than a username / password as this is what the app uses for authentication.
2. Launch docker compose with the warehouse you would like:
* For Snowflake streaming loader use:  `docker-compose --profile snowflake-loader up` which will launch the normal components + the Snowflake Kinesis loader.
* For the Lake loader use `--profile lake-loader`.
* For the BigQuery loader use `--profile bigquery-loader`.
3. Send some events!

You can optionally start an additional loader for incomplete events (for Snowflake only currently) by adding `--profile snowflake-incomplete-loader`.

## Configuring the collector

The collector runs with mostly default settings, other than faster drain / reboot times. You can configure the collector settings in `collector/config.hocon`. You can find documentation on the collector [here](https://docs.snowplow.io/docs/pipeline-components-and-applications/stream-collector/configure/).

## Configuring enrich

The enrichment process runs with mostly default settings. You can configure the enrichment process in `enrich/enrich.hocon`. Enrichments are read on startup from the `enrich/enrichments` directory.

As part of the enrichment process (to enable seamless patching) the Iglu client uses a resolver with a cacheSize of 0 which avoids it caching schemas from Iglu Server. This reduces the performance of the pipeline in favour of a simpler development experience. In a production context this value is often significantly higher (e.g., 500). You can modify the resolver settings in `iglu-client/resolver.json` which will be used by any components that query Iglu Server.

You can find documentation on how to configure the enrichment process [here](https://docs.snowplow.io/docs/pipeline-components-and-applications/enrichment-components/configuration-reference/).

## Configuring Iglu Server

Iglu Server primarily uses defaults with the exception of:
`debug` which is set to true to aid in easier debugging (in addition to exposting meta endpoints).
`patchesAllowed` which allows schemas of the same version to be patched even if they already exist - this tends to be useful in a development context but it something to be avoided in production.

You can configure Iglu Server in `iglu-server/config.hocon` and find more information about the configuration options [here](https://docs.snowplow.io/docs/pipeline-components-and-applications/iglu/iglu-repositories/iglu-server/reference/).

### Configuring Snowbridge

If you would like to run [Snowbridge](https://docs.snowplow.io/docs/destinations/forwarding-events/snowbridge/) locally you can use `--profile snowbridge` which will start Snowbridge as part of the pipeline. By default it will read from the `enriched-good` stream. This behaviour (including transformations, destinations etc) can be configured as part of the HCL configuration file in `snowbridge/config.hcl`.

This configuration writes to stdout for both the successful and failure targets for easier debugging but this can be changed easily in the configuration file.

By default Snowbridge uses `TRIM_HORIZON` to read from the Kinesis enriched stream. If you do not want this behaviour and instead want something that resembles `LATEST` you can set an environment variable when running docker compose to avoid processing older events e.g.,

`export START_TIMESTAMP =$(date +"%Y-%m-%d %H:%M:%S") && docker-compose --profile snowbridge up`

The syntax for this command may vary slightly depending on your shell. You can find more information on running and configuring Snowbridge [here](https://docs.snowplow.io/docs/destinations/forwarding-events/snowbridge/configuration/).

## Supported components

* [Scala stream collector](https://docs.snowplow.io/docs/pipeline-components-and-applications/stream-collector/) 3.2.0
* [Enrich](https://docs.snowplow.io/docs/pipeline-components-and-applications/enrichment-components/enrich-kinesis/) 5.0.0
* [Iglu Server](https://docs.snowplow.io/docs/pipeline-components-and-applications/iglu/iglu-repositories/iglu-server/) 0.12.1
* [Javascript tracker](https://docs.snowplow.io/docs/collecting-data/collecting-from-own-applications/javascript-trackers/) 3.23
* [Snowflake streaming loader](https://docs.snowplow.io/docs/pipeline-components-and-applications/loaders-storage-targets/snowflake-streaming-loader/) 0.2.4
* [Lake Loader](https://docs.snowplow.io/docs/pipeline-components-and-applications/loaders-storage-targets/lake-loader/) 0.5.0
* [BigQuery loader](https://docs.snowplow.io/docs/pipeline-components-and-applications/loaders-storage-targets/bigquery-loader/#streamloader) (2.0.0-rc10)
* [Snowbridge](https://docs.snowplow.io/docs/destinations/forwarding-events/snowbridge/) 2.4.2

Under the hood Localstack is used to simulate the AWS components - primarily used for service messaging (Kinesis and Dynamodb) including the communication between the collector and the enricher as well as checkpointing for KCL. Localstack also provides a mock S3 service that you can use if you wish to use the Lake Loader to write to S3 (which in turn uses the local filesystem rather than AWS S3). By default Localstack will persist state to disk.

## Monitoring

This setup includes a Grafana instance that can be accessed at [http://localhost:3000](http://localhost:3000) with the default credentials of `admin:admin`. Many Snowplow components will emit metrics to statsd and as a result become available in Grafana (via Graphite). A default Graphite source is setup for you in Grafana so you should not need to connect this.

Logs for components that write them (e.g., collector, enrich) are written to Cloudwatch on Localstack.

The storage for Grafana is also mounted as a volume so you can persist any dashboards and data across restarts, rather than losing them on reboot!

## Gotchas

### Snowflake loader
Snowflake requires your private key to be specified on a single line with the private key header, footer and any newlines removed. To do this you can run `cat <filepath/rsa_key1.p8> | grep -v PRIVATE | tr -d '\n\r'` and paste it in your `.env` file.


### BigQuery loader
BigQuery requires a service account key to be specified. Currently this needs to be done on the command line rather than passed in via the `.env` file. To do this set an environment variable `SERVICE_ACCOUNT_CREDENTIALS` in your terminal _before_ running `docker compose up`.

e.g., for BASH use
```bash
export SERVICE_ACCOUNT_CREDENTIALS=$(cat /path/to/your/service-account-key.json)
```

## Incomplete events

Currently incomplete events load into the same table as successful events. This is deliberate - but can be overwritten by specifying a different table in the `incomplete` loader HOCON configuration file.

Incomplete events can be enabled by using the `--profile incomplete` flag when running docker-compose. Currently this only works for the Snowflake streaming loader but plans are in place to allow this to work for other loaders as well (please create a Github issue if you have specific requests).

Events that are incomplete can be identified in the warehouse by querying for the context being non-null i.e.,

```
FROM
    events
WHERE
    CONTEXTS_COM_SNOWPLOWANALYTICS_SNOWPLOW_FAILURE_1 IS NOT NULL
```

If you'd like to fire some example incomplete events you can do so from the [kitchen sink page](http://localhost:8082).

## Differences to existing Snowplow software

- How is this different from Snowplow Micro?

[Snowplow Micro](https://docs.snowplow.io/docs/testing-debugging/snowplow-micro/what-is-micro/) is ideal for environments where you want a small asset or to quickstart sending and testing events into a pipeline in a single, simple asset.

It stores events in-memory rather than a warehouse, so a reboot of the container will lose any stored data.

Micro provides a simple API endpoint that allows for you to assert against what data has been collected, and whether it has been validated which is useful in debugging and CI/CD contexts.

- How is this different from Snowplow Mini?

[Snowplow Mini](https://docs.snowplow.io/docs/pipeline-components-and-applications/snowplow-mini/overview/) is a more fully fledged version of the Snowplow pipeline that typically runs as an image on a virtual machine. It includes additional components - like it's own Iglu registry and messaging bus (NSQ) and stores data in an Opensearch cluster allowing it to persist between restarts.

- What makes Snowplow Local different?

Snowplow local aims to recreate some of the best parts of Micro and Mini whilst enabling warehouse loading. Similar to Mini it runs a full version of the collector, enricher and other Snowplow components as well as optional loaders.

In addition it uses Localstack to mock out the AWS services that Snowplow typically uses (Kinesis, DynamoDB, S3). This not only makes it straightforward to start up (no AWS account required!) but also allows you to connect to remote services - like S3 or GCS if required to store data.

Metrics and logging are also provided out of the box - making it easier to debug things like latencies for enrichments, or customisations that you might want to make.

Some default behaviours have also been changed that make it easier to develop and iterate on schemas by patching them live without having to reboot the enrichment process.

Finally, the local version also includes full support for incomplete events as part of the latest version of enrich - making failed events more accessible and easier to debug than ever before.

## Known issues

The KCL, specifically within enrich has a pesty habit of being slow to 'steal' leases and start processing data on initial startup. Although events can be collected immediately it may take up to 60 seconds on subsequent startups for enrich to start enriching events. Once this period has passed everything works as per normal.

## Copyright and license

Snowplow is copyright 2024 Snowplow Analytics Ltd.