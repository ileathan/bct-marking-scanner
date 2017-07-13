
# UNDER MAINTANENCE - currently the only way to get this working is to examine the code for the database structure and then populate your database users and marking balances. I will revisit this code and make it self populating soon.

# bct-marking-scanner
Scans all posts from all known potential marking users for marks.

# Dependencies

1.) Perl, this should already be installed on your system.
2.) UserAgent `cpan install LWP::UserAgent` our crawler.
3.) SQLite `cpan install DBD::SQLite` our database.


Simply run the scanner.pl to process ALL markings on ALL users. Its recommended to set a cronjob to run the file every 15minnutes to a couple hours.

You must be running an SQLite dataase daemon, currently there is no one maintaining a database and hence the initial database must be populated as such.

# Database name

```
usersdb
```

# Configuration

The database needs 4 tables, allUsers, balance, accounts, transactions.

