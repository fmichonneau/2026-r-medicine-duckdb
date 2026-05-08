## Make sure you have the {duckdb} and {dplyr} packages installed.

library(duckdb)
library(dplyr)

## Follow along the tutorial by typing the code in this file.

## The data dictionary for the dataset is available at:
## https://www2.census.gov/programs-surveys/acs/tech_docs/pums/data_dict/PUMS_Data_Dictionary_2021.txt

## Whenever you calculate a count, total, or average from PUMS data, use PWGTP. Raw record counts are
# almost meaningless on their own — a table of 100,000 rows doesn't represent 100,000 people;
# it represents the sum of their PWGTP values, which could be in the tens of millions.

## Data set exploration with DuckDB

con <- dbConnect(duckdb(), ":memory:")

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |> 
  head()

tbl(con, "read_parquet('data/pums_person_sample.parquet')")

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |> 
  colnames()

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |> 
  tail()

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |> 
  count()

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |>
  distinct(ST)

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |>
  distinct(ST, year)

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |>
  distinct(ST, year) |> 
  arrange(ST, year)

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |>
  distinct(ST, year) |> 
  arrange(ST, year) |> 
  collect()

tbl(con, "read_parquet('data/pums_person_sample.parquet')") |>
  summarize(n = sum(PWGTP, na.rm = TRUE), .by = c(ST, year)) |> 
  arrange(ST, year) |> 
  collect()

dbDisconnect(con)

## Using DuckDB files to save tables
##
## everything up to this point, very exploratory. we didn't save anything. Need
## to recalculate if doing it again. And we read from the same file every time.
## If the file was much larger, that would be inefficient.

con <- dbConnect(duckdb(), dbdir = "pums-small.duckdb", read_only = FALSE)

## Create the table using SQL. This approach scales to very large datasets.

dbExecute(
  con,
  "
  CREATE TABLE pums_person_small AS SELECT * FROM read_parquet('data/pums_person_sample.parquet');
  "
)
dbListTables(con)

## Create the mean_commute_time table
##
## Here, we also show another way of creating a table within the database
## using the dbWriteTable() function.

mean_commute_time <- tbl(con, "pums_person_small") |> 
  summarize(
    mean_commute_time = sum(JWMNP * PWGTP, na.rm = TRUE) / sum(PWGTP),
    .by = c(ST, year)
  ) |> 
  collect()

dbWriteTable(con, "mean_commute_time", mean_commute_time)
dbListTables(con)

tbl(con, "mean_commute_time")
dbDisconnect(con)
rm(con)

## More advanced data manipulation
## Using DuckDB functions in mutate()

con <- dbConnect(duckdb(), "pums-small.duckdb")
dbListTables(con)

tbl(con, "pums_person_small") |> 
  select(ST, year, JWMNP, PWGTP, OCCP) |> 
  filter(!is.na(JWMNP)) |> 
  #mutate(category = stringr::str_split_i(OCCP, "-", 1)) # this doesn't work unless you bring the data in R's memory first
  mutate(category = sql("split_part(OCCP, '-', 1)"))


# using just SQL, you can create a table directly from a query
# so you don't have to put the table in R's memory.
# This approach works with data that doesn't fit in memory

dbGetQuery(
  con,
  "
  SELECT ST, year, DRIVESP, PWGTP, split_part(DRIVESP, ' ', 1)::FLOAT AS carpool
  FROM pums_person_small
  WHERE DRIVESP NOT NULL
  "
) |> as_tibble()

dbExecute(
  con,
  "
  CREATE TABLE carpool AS (
  SELECT ST, year, DRIVESP, PWGTP, split_part(DRIVESP, ' ', 1)::FLOAT AS carpool
  FROM pums_person_small
  WHERE DRIVESP NOT NULL
);
  "
)

## Now you can use this table in your analysis

tbl(con, "carpool") |> 
  summarize(carpool = sum(PWGTP * carpool) / sum(PWGTP), .by = c("ST", "year")) |> 
  arrange(ST, year) |> 
  collect()

## Practice
##
## The JWAP column contains the time of arrival at work. The data is reported
## as a text string such as '8:00 a.m. to 8:04 a.m.'. We want to extract the
## the first time reported in this column (here 8.00 a.m.) and put it in a
## a column where it is correctly stored as a time data type.
## Hint: we'll use the replace(), trim(), split_part(), and strptime() functions
## from DuckDB to extract the time. The format specifier for strptime for the
## time is '%I:%M %p'.
##
## Note: contrary to {dplyr}, you can't reuse a mutated column in a single
## mutate() call. You need to call the mutate() function multiple times.

tbl(con, "pums_person_small") |> 
  select(ST, year, JWAP) |> 
  filter(!is.na(JWAP)) |> 
  mutate(time_start = sql("replace(JWAP, '.', '')")) |> 
  mutate(
    time_start = sql("strptime(split_part(time_start, ' to ', 1), '%I:%M %p')::TIME")
  ) |> 
  collect(n = 1000)
