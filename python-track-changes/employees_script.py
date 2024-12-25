import pandas as pd
import sqlite3

# pip install sqlite-history

# Connect to SQLite database (or create it if it doesn't exist)
cnx = sqlite3.connect("employees.db")


# Define the Employee class
class Employee:
    def __init__(self, id, name, age, department):
        self.id = id
        self.name = name
        self.age = age
        self.department = department

    @classmethod
    def create_table(cls, cnx):
        query = """
        CREATE TABLE IF NOT EXISTS employee (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            age INTEGER NOT NULL,
            department TEXT NOT NULL
        )
        """
        cnx.execute(query)
        cnx.commit()


# Function to list all data from the employee table
def list_all_data():
    query = "SELECT * FROM employee"
    df = pd.read_sql(query, cnx)
    # df = pd.read_sql_table('employee', conn)
    print(df)


# Create the employee table
def create_table():
    print("[+] Creating employee table")
    Employee.create_table(cnx)

    # ddl = pd.io.sql.get_schema(df, 'employee')
    # ddl = pd.io.sql.get_schema(df, 'employee', con=engine)
    # print(f"Table DDL: {ddl}")


def main():
    print("[+] Running Script")

    create_table()

    print("[+] BEFORE INSERTING NEW DATA")

    list_all_data()

    # Create initial data as Employee objects
    employees = [
        Employee(1, "Alice", 25, "HR"),
        Employee(2, "Bob", 30, "Engineering"),
        Employee(3, "Charlie", 35, "Sales"),
        # Employee(4, "VIZ", 21, "Eng"),
        # Employee(5, "SONI", 22, "Engineering"),
    ]

    # Convert Employee objects to a DataFrame
    initial_df = pd.DataFrame([vars(e) for e in employees])

    print("[+] Inserting new data")
    # Write the DataFrame to the SQLite database (it will create the table automatically)
    initial_df.to_sql("employee", cnx, if_exists="append", index=False)

    print("[+] AFTER INSERTING NEW DATA")
    # List all data after inserting new data
    list_all_data()

    # Close the connection
    cnx.close()


if __name__ == "__main__":
    main()
