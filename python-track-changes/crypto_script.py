from dbm import sqlite3

# Open the database file
with sqlite3.open('crypto.db', 'c') as db:
    # Display all records in the table
    print("Current records in the database:")
    for key in db.keys():
        print(f"{key.decode('utf-8')}: {db[key].decode('utf-8')}")

    # Insert some data
    db['bitcoin'] = 'BTC'
    db['ethereum'] = 'ETH'
    db['ripple'] = 'changes'
    db['okay'] = 'bye'

    # Display all records after insertion
    print("\nRecords after insertion:")
    for key in db.keys():
        print(f"{key.decode('utf-8')}: {db[key].decode('utf-8')}")