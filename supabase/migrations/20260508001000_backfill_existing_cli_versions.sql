-- Existing installs predate CLI version reporting. Mark them as the previous
-- release so the app can prompt those users to rerun the curl installer.

update installations
set cli_version = '0.3.8'
where cli_version is null;
