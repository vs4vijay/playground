import pandas as pd
import sqlite3

# Connect to SQLite database (or create it if it doesn't exist)
conn = sqlite3.connect('employee.db')

# Function to list all data from the employee table
def list_all_data():
    query = "SELECT * FROM employee"
    df = pd.read_sql(query, conn)
    print(df)

# Define the Employee class
class Employee:
    def __init__(self, id, name, age, department):
        self.id = id
        self.name = name
        self.age = age
        self.department = department

def main():
    # Create initial data as Employee objects
    employees = [
        Employee(1, 'Alice', 25, 'HR'),
        Employee(2, 'Bob', 30, 'Engineering'),
        Employee(3, 'Charlie', 35, 'Sales')
    ]

    # Convert Employee objects to a DataFrame
    initial_data = {
        'id': [e.id for e in employees],
        'name': [e.name for e in employees],
        'age': [e.age for e in employees],
        'department': [e.department for e in employees]
    }
    initial_df = pd.DataFrame(initial_data)

    # List all data before inserting new data
    list_all_data()

    # Write the DataFrame to the SQLite database (it will create the table automatically)
    initial_df.to_sql('employee', conn, if_exists='replace', index=False)

    # List all data after inserting new data
    list_all_data()

    # Close the connection
    conn.close()

if __name__ == "__main__":
    main()