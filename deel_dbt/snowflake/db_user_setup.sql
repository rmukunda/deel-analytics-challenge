
CREATE DATABASE DEEL;

-- ============================================
-- WAREHOUSE
-- ============================================
-- Small warehouse dedicated to dbt Cloud runs against DEEL. Auto-suspend
-- keeps it from burning credits between runs; size can be revisited once
-- actual run times/concurrency are known.
CREATE WAREHOUSE IF NOT EXISTS DBT_WORKLOAD
  WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for dbt Cloud runs against DEEL';

-- ============================================
-- READ-ONLY ROLE
-- ============================================
CREATE ROLE IF NOT EXISTS DEEL_READ_ONLY;

GRANT USAGE ON DATABASE DEEL TO ROLE DEEL_READ_ONLY;

GRANT USAGE ON ALL SCHEMAS IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;

GRANT SELECT ON ALL TABLES IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;
GRANT SELECT ON FUTURE TABLES IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;

GRANT SELECT ON ALL VIEWS IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;
GRANT SELECT ON FUTURE VIEWS IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;

GRANT SELECT ON ALL MATERIALIZED VIEWS IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;
GRANT SELECT ON FUTURE MATERIALIZED VIEWS IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;

GRANT SELECT ON ALL DYNAMIC TABLES IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN DATABASE DEEL TO ROLE DEEL_READ_ONLY;


-- ============================================
-- READ-WRITE ROLE (inherits read-only)
-- ============================================
CREATE ROLE IF NOT EXISTS DEEL_READ_WRITE;

GRANT ROLE DEEL_READ_ONLY TO ROLE DEEL_READ_WRITE;

GRANT USAGE, CREATE SCHEMA ON DATABASE DEEL TO ROLE DEEL_READ_WRITE;

GRANT USAGE ON WAREHOUSE DBT_WORKLOAD TO ROLE DEEL_READ_WRITE;

GRANT USAGE ON ALL SCHEMAS IN DATABASE DEEL TO ROLE DEEL_READ_WRITE;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE DEEL TO ROLE DEEL_READ_WRITE;

-- DML on tables
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN DATABASE DEEL TO ROLE DEEL_READ_WRITE;
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON FUTURE TABLES IN DATABASE DEEL TO ROLE DEEL_READ_WRITE;

-- DDL, so dbt can create/replace objects per schema
GRANT CREATE TABLE, CREATE VIEW, CREATE STAGE, CREATE FILE FORMAT, CREATE DYNAMIC TABLE
  ON ALL SCHEMAS IN DATABASE DEEL TO ROLE DEEL_READ_WRITE;
GRANT CREATE TABLE, CREATE VIEW, CREATE STAGE, CREATE FILE FORMAT, CREATE DYNAMIC TABLE
  ON FUTURE SCHEMAS IN DATABASE DEEL TO ROLE DEEL_READ_WRITE;

-- ============================================================
-- SETUP: dbt_runner SERVICE USER (from scratch)
-- Creates the user, assigns its role, attaches a network policy,
-- and issues a PAT for dbt Cloud runs against DEEL.
--
-- Run as SECURITYADMIN (or a role with CREATE USER / CREATE
-- NETWORK POLICY / MANAGE GRANTS privileges).
--
-- Assumptions to verify before running:
--   - Role DEEL_READ_WRITE already exists (create it first if not)
--   - Warehouse DBT_WORKLOAD already exists (created above)
--   - Replace the placeholder IP list below
-- ============================================================

USE ROLE SECURITYADMIN;

-- ============================================
-- 1. CREATE THE NETWORK POLICY (first, so it can
--    be attached inline at user-creation time)
-- ============================================
-- Simple version: direct IP allow list. 0.0.0.0/0 is a placeholder --
-- replace with dbt Cloud's published egress IP ranges before running
-- this in production.
CREATE NETWORK POLICY IF NOT EXISTS DBT_RUNNER_NETWORK_POLICY
  ALLOWED_IP_LIST = ('0.0.0.0/0')
  COMMENT = 'Restricts dbt_runner service user to known dbt Cloud egress IPs';

-- ============================================
-- 2. CREATE THE SERVICE USER
-- ============================================
-- Service users can't use passwords/MFA -- only key-pair or PAT auth,
-- so no password is ever set here. NETWORK_POLICY is attached inline
-- since the policy already exists (no separate ALTER needed for this part).
CREATE USER IF NOT EXISTS dbt_runner
  TYPE = SERVICE
  DEFAULT_ROLE = DEEL_READ_WRITE
  DEFAULT_WAREHOUSE = 'DBT_WORKLOAD'
  NETWORK_POLICY = DBT_RUNNER_NETWORK_POLICY
  COMMENT = 'Service user for dbt Cloud runs against DEEL';

-- ============================================
-- 3. ROLE ASSIGNMENT
-- ============================================
GRANT ROLE DEEL_READ_WRITE TO USER dbt_runner;

-- ============================================
-- 4. CREATE THE PAT
-- ============================================
-- PATs have no CREATE USER equivalent -- ADD PROGRAMMATIC ACCESS TOKEN
-- only exists as an ALTER USER action, so this step still has to come
-- after the user exists, even though the policy could be set inline above.
-- TYPE = SERVICE requires ROLE_RESTRICTION on the token.
-- The token secret is returned exactly once in the result set --
-- capture it immediately and store it in your secrets manager /
-- dbt Cloud environment variable; Snowflake will not show it again.
ALTER USER dbt_runner ADD PROGRAMMATIC ACCESS TOKEN dbt_runner_token
  ROLE_RESTRICTION = 'DEEL_READ_WRITE'
  DAYS_TO_EXPIRY = 90
  COMMENT = 'PAT for dbt Cloud runs against DEEL';



GRANT ROLE DEEL_READ_WRITE TO USER dbt_runner;

-- ============================================
-- 5. VERIFY
-- ============================================
DESC USER dbt_runner;
SHOW NETWORK POLICIES LIKE 'DBT_RUNNER_NETWORK_POLICY';
SHOW GRANTS TO USER dbt_runner;
SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER dbt_runner;