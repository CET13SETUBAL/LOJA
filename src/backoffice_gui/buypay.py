import sys
import os
import configparser
import hashlib
import base64
import subprocess
from datetime import datetime, date
from cryptography.fernet import Fernet
from PySide6.QtWidgets import QHeaderView
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                              QHBoxLayout, QLabel, QLineEdit, QPushButton, 
                              QTabWidget, QTableWidget, QTableWidgetItem, QComboBox, 
                              QDateEdit, QMessageBox, QDialog, QCheckBox, QGroupBox,
                              QSpinBox, QDoubleSpinBox, QTextEdit, QFileDialog)
from PySide6.QtCore import Qt, QDate
import mysql.connector



def exec_script_mysql(ficheiro_sql, host, user, password, database):
    if not os.path.exists(ficheiro_sql):
        print(f"❌ Ficheiro não encontrado: {ficheiro_sql}")
        return

    conn = mysql.connector.connect(
        host=host,
        user=user,
        password=password,
        database=database,
        autocommit=True
    )
    cursor = conn.cursor()

    with open(ficheiro_sql, 'r', encoding='utf-8') as f:
        script = f.read()

    comandos = []
    delimitador = ';'
    buffer = ''

    for linha in script.splitlines():
        linha_strip = linha.strip()
        if linha_strip.lower().startswith('delimiter'):
            delimitador = linha_strip.split()[1]
            continue

        buffer += linha + '\n'
        if buffer.strip().endswith(delimitador):
            comandos.append(buffer.strip()[:-len(delimitador)].strip())
            buffer = ''

    for comando in comandos:
        try:
            cursor.execute(comando)
            print(f"✅ Executado: {comando.splitlines()[0][:80]}...")
        except Exception as e:
            print(f"❌ Erro:\n{comando[:200]}\n→ {e}\n")

    cursor.close()
    conn.close()

class ConfigManager:
    """Handles encrypted configuration for storing operator credentials"""
    def __init__(self, config_file='config.ini'):
        self.config_file = config_file
        self.key = self.get_or_create_key()
        self.fernet = Fernet(self.key)
        self.config = configparser.ConfigParser()
    
    def get_or_create_key(self):
        """Get existing key or create a new one"""
        key_file = '.buypy.key'
        if os.path.exists(key_file):
            with open(key_file, 'rb') as f:
                return f.read()
        else:
            key = Fernet.generate_key()
            with open(key_file, 'wb') as f:
                f.write(key)
            # Set restrictive permissions on key file
            os.chmod(key_file, 0o600)
            return key
    
    def save_config(self, username, password):
        """Save encrypted operator credentials"""
        self.config['Operator'] = {
            'username': self.encrypt(username),
            'password': self.encrypt(password)
        }
        
        with open(self.config_file, 'w') as f:
            self.config.write(f)
    
    def load_config(self):
        """Load and decrypt operator credentials"""
        if not os.path.exists(self.config_file):
            return None, None
        
        self.config.read(self.config_file)
        if 'Operator' not in self.config:
            return None, None
        
        try:
            username = self.decrypt(self.config['Operator']['username'])
            password = self.decrypt(self.config['Operator']['password'])
            return username, password
        except:
            return None, None
    
    def encrypt(self, text):
        """Encrypt text data"""
        return self.fernet.encrypt(text.encode()).decode()
    
    def decrypt(self, encrypted_text):
        """Decrypt text data"""
        return self.fernet.decrypt(encrypted_text.encode()).decode()
    
    def clear_config(self):
        """Remove configuration file (logout)"""
        if os.path.exists(self.config_file):
            os.remove(self.config_file)


class DatabaseManager:
    """Handles database connections and operations"""
    def __init__(self):
        self.connection = None
    
    def connect(self, username, password, host='localhost', database='BuyPay'):
        """Connect to the database"""
        try:
            if LoginDialog.database==0:
                print("\nlogado\n")

                #exec_script_mysql("BUYPY.sql", "localhost", "adminis", "ZZtopes!23", "sys")
            else:
                print("\nnao logado\n")   
            self.connection = mysql.connector.connect(
                host=host,
                user=username,
                password=password,
                database=database
            )
            return True
        except mysql.connector.Error as err:
            print(f"Database connection error: {err}")
            return False
    
    def disconnect(self):
        """Close database connection"""
        if self.connection and self.connection.is_connected():
            self.connection.close()
    
    def search_user_by_id(self, user_id):
        """Search for a user by ID"""
        cursor = self.connection.cursor(dictionary=True)
        cursor.execute("""
            SELECT customer_id, first_name, last_name, email, address, postal_code, 
                   city, country, phone, status
            FROM Customer
            WHERE customer_id = %s
        """, (user_id,))
        result = cursor.fetchone()
        cursor.close()
        return result
    
    def search_user_by_username(self, username):
        """Search for a user by username (email)"""
        cursor = self.connection.cursor(dictionary=True)
        cursor.execute("""
            SELECT customer_id, first_name, last_name, email, address, postal_code, 
                   city, country, phone, status
            FROM Customer
            WHERE email = %s
        """, (username,))
        result = cursor.fetchone()
        cursor.close()
        return result
    
    def update_user_status(self, user_id, new_status):
        """Update a user's status (active, inactive, blocked)"""
        cursor = self.connection.cursor()
        cursor.execute("""
            UPDATE Customer
            SET status = %s
            WHERE customer_id = %s
        """, (new_status, user_id))
        self.connection.commit()
        cursor.close()
        return cursor.rowcount > 0
    
    def get_blocked_users(self):
        """Get a list of all blocked users"""
        cursor = self.connection.cursor(dictionary=True)
        cursor.execute("""
            SELECT customer_id, first_name, last_name, email, city, postal_code, status
            FROM Customer
            WHERE status = 'blocked'
        """)
        results = cursor.fetchall()
        cursor.close()
        return results
    
    def get_products(self, product_type=None, min_qty=None, max_qty=None, min_price=None, max_price=None):
        """Get products with optional filters"""
        cursor = self.connection.cursor(dictionary=True)
        
        query = """
            SELECT p.product_id, p.price, p.quantity, p.active,
                   CASE
                       WHEN b.isbn IS NOT NULL THEN 'Book'
                       ELSE 'Electronics'
                   END AS product_type,
                   COALESCE(b.title, CONCAT(e.brand, ' ', e.model)) AS description
            FROM Product p
            LEFT JOIN Book b ON p.product_id = b.product_id
            LEFT JOIN Electronics e ON p.product_id = e.product_id
            WHERE 1=1
        """
        params = []
        
        if product_type:
            if product_type == 'Book':
                query += " AND b.isbn IS NOT NULL"
            elif product_type == 'Electronics':
                query += " AND e.serial_number IS NOT NULL"
        
        if min_qty is not None:
            query += " AND p.quantity >= %s"
            params.append(min_qty)
        
        if max_qty is not None:
            query += " AND p.quantity <= %s"
            params.append(max_qty)
        
        if min_price is not None:
            query += " AND p.price >= %s"
            params.append(min_price)
        
        if max_price is not None:
            query += " AND p.price <= %s"
            params.append(max_price)
        
        cursor.execute(query, params)
        results = cursor.fetchall()
        cursor.close()
        return results
    
    def add_book(self, quantity, price, vat_rate, popularity, image_path, isbn, title, 
                 genre, publisher, author, publication_date):
        """Add a new book product"""
        cursor = self.connection.cursor()
        try:
            cursor.callproc('AddBook', 
                           [quantity, price, vat_rate, popularity, image_path, isbn, 
                            title, genre, publisher, author, publication_date])
            self.connection.commit()
            return True
        except mysql.connector.Error as err:
            print(f"Error adding book: {err}")
            return False
        finally:
            cursor.close()
    
    def add_electronics(self, quantity, price, vat_rate, popularity, image_path, 
                        serial_number, brand, model, tech_specs, product_type):
        """Add a new electronics product"""
        cursor = self.connection.cursor()
        try:
            cursor.callproc('AddElec', 
                           [quantity, price, vat_rate, popularity, image_path,
                            serial_number, brand, model, tech_specs, product_type])
            self.connection.commit()
            return True
        except mysql.connector.Error as err:
            print(f"Error adding electronics: {err}")
            return False
        finally:
            cursor.close()


class LoginDialog(QDialog):
    """Dialog for operator login"""
    database=0

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("BuyPy Backoffice - Login")
        self.setMinimumWidth(300)
        LoginDialog.database=1        
        layout = QVBoxLayout()
        
        # Username field
        username_layout = QHBoxLayout()
        username_layout.addWidget(QLabel("Username:"))
        self.username_input = QLineEdit()
        username_layout.addWidget(self.username_input)
        layout.addLayout(username_layout)
        
        # Password field
        password_layout = QHBoxLayout()
        password_layout.addWidget(QLabel("Password:"))
        self.password_input = QLineEdit()
        self.password_input.setEchoMode(QLineEdit.Password)
        password_layout.addWidget(self.password_input)
        layout.addLayout(password_layout)
        
        # Login button
        self.login_button = QPushButton("Login")
        self.login_button.clicked.connect(self.accept)
        layout.addWidget(self.login_button)
        
        # Cancel button
        self.cancel_button = QPushButton("Cancel")
        self.cancel_button.clicked.connect(self.reject)
        layout.addWidget(self.cancel_button)
        
        self.setLayout(layout)
    
    def get_credentials(self):
        """Return entered username and password"""
        return self.username_input.text(), self.password_input.text()


class AdminDialog(QDialog):
    """Dialog for searching users"""
    def __init__(self, db_manager, parent=None):
        super().__init__(parent)
        self.db_manager = db_manager
        self.setWindowTitle("Search User")
        self.setMinimumWidth(400)

class UserSearchDialog(QDialog):
    """Dialog for searching users"""
    def __init__(self, db_manager, parent=None):
        super().__init__(parent)
        self.db_manager = db_manager
        self.setWindowTitle("Search User")
        self.setMinimumWidth(400)
        
        layout = QVBoxLayout()
        
        # Search by ID
        id_layout = QHBoxLayout()
        id_layout.addWidget(QLabel("User ID:"))
        self.id_input = QLineEdit()
        id_layout.addWidget(self.id_input)
        self.search_id_button = QPushButton("Search by ID")
        self.search_id_button.clicked.connect(self.search_by_id)
        id_layout.addWidget(self.search_id_button)
        layout.addLayout(id_layout)
        
        # Search by username
        username_layout = QHBoxLayout()
        username_layout.addWidget(QLabel("Username:"))
        self.username_input = QLineEdit()
        username_layout.addWidget(self.username_input)
        self.search_username_button = QPushButton("Search by Username")
        self.search_username_button.clicked.connect(self.search_by_username)
        username_layout.addWidget(self.search_username_button)
        layout.addLayout(username_layout)
        
        # Results table
        self.results_table = QTableWidget(0, 6)
        self.results_table.setHorizontalHeaderLabels(
            ["ID", "Name", "Email", "City", "Status", "Actions"]
        )
        layout.addWidget(self.results_table)
        
        # Close button
        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.accept)
        layout.addWidget(self.close_button)
        
        self.setLayout(layout)
        
        # Resize columns
        header = self.results_table.horizontalHeader()
        for i in range(5):
            header.setSectionResizeMode(i, QHeaderView.ResizeToContents)
    #        header.setSectionResizeMode(i, QTableWidget.resizeRowsToContents)
    #table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeToContents)

    
    def search_by_id(self):
        """Search for user by ID"""
        user_id = self.id_input.text().strip()
        if not user_id:
            QMessageBox.warning(self, "Input Error", "Please enter a valid user ID")
            return
        
        try:
            user_id = int(user_id)
        except ValueError:
            QMessageBox.warning(self, "Input Error", "User ID must be a number")
            return
        
        user = self.db_manager.search_user_by_id(user_id)
        self.display_results([user] if user else [])
    
    def search_by_username(self):
        """Search for user by username (email)"""
        username = self.username_input.text().strip()
        if not username:
            QMessageBox.warning(self, "Input Error", "Please enter a username")
            return
        
        user = self.db_manager.search_user_by_username(username)
        self.display_results([user] if user else [])
    
    def display_results(self, users):
        """Display search results in the table"""
        self.results_table.setRowCount(0)
        
        if not users or all(user is None for user in users):
            QMessageBox.information(self, "Search Results", "No users found matching the criteria")
            return
        
        for user in users:
            if user is None:
                continue
                
            row = self.results_table.rowCount()
            self.results_table.insertRow(row)
            
            # Add user data
            self.results_table.setItem(row, 0, QTableWidgetItem(str(user['customer_id'])))
            self.results_table.setItem(row, 1, QTableWidgetItem(
                f"{user['first_name']} {user['last_name']}"
            ))
            self.results_table.setItem(row, 2, QTableWidgetItem(user['email']))
            self.results_table.setItem(row, 3, QTableWidgetItem(user['city']))
            self.results_table.setItem(row, 4, QTableWidgetItem(user['status']))
            
            # Add action button
            action_text = "Block" if user['status'] != 'blocked' else "Unblock"
            action_button = QPushButton(action_text)
            action_button.clicked.connect(lambda checked, uid=user['customer_id'], 
                                                 current_status=user['status']:
                                         self.toggle_user_status(uid, current_status))
            self.results_table.setCellWidget(row, 5, action_button)
    
    def toggle_user_status(self, user_id, current_status):
        """Toggle user status between blocked and active"""
        new_status = 'blocked' if current_status != 'blocked' else 'active'
        
        if self.db_manager.update_user_status(user_id, new_status):
            QMessageBox.information(self, "Success", 
                                   f"User {user_id} status changed to {new_status}")
            
            # Refresh the display
            if new_status == 'blocked':
                # If we just blocked a user that was found by ID, refresh that search
                if self.id_input.text() and int(self.id_input.text()) == user_id:
                    self.search_by_id()
                # If we just blocked a user that was found by username, refresh that search
                elif self.username_input.text():
                    self.search_by_username()
            else:
                # If we just unblocked a user, they won't show up in the blocked users list anymore
                # So we should refresh the current search
                if self.id_input.text() and int(self.id_input.text()) == user_id:
                    self.search_by_id()
                elif self.username_input.text():
                    self.search_by_username()
        else:
            QMessageBox.warning(self, "Error", "Failed to update user status")


class BlockedUsersDialog(QDialog):
    """Dialog for showing all blocked users"""
    def __init__(self, db_manager, parent=None):
        super().__init__(parent)
        self.db_manager = db_manager
        self.setWindowTitle("Blocked Users")
        self.setMinimumWidth(600)
        self.setMinimumHeight(400)
        
        layout = QVBoxLayout()
        
        # Results table
        self.results_table = QTableWidget(0, 6)
        self.results_table.setHorizontalHeaderLabels(
            ["ID", "Name", "Email", "City", "Postal Code", "Actions"]
        )
        layout.addWidget(self.results_table)
        
        # Refresh and Close buttons
        button_layout = QHBoxLayout()
        self.refresh_button = QPushButton("Refresh")
        self.refresh_button.clicked.connect(self.load_blocked_users)
        button_layout.addWidget(self.refresh_button)
        
        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.accept)
        button_layout.addWidget(self.close_button)
        
        layout.addLayout(button_layout)
        
        self.setLayout(layout)
        
        # Load blocked users when dialog opens
        self.load_blocked_users()
    
    def load_blocked_users(self):
        """Load and display all blocked users"""
        blocked_users = self.db_manager.get_blocked_users()
        
        self.results_table.setRowCount(0)
        
        if not blocked_users:
            QMessageBox.information(self, "Blocked Users", "No blocked users found")
            return
        
        for user in blocked_users:
            row = self.results_table.rowCount()
            self.results_table.insertRow(row)
            
            # Add user data
            self.results_table.setItem(row, 0, QTableWidgetItem(str(user['customer_id'])))
            self.results_table.setItem(row, 1, QTableWidgetItem(
                f"{user['first_name']} {user['last_name']}"
            ))
            self.results_table.setItem(row, 2, QTableWidgetItem(user['email']))
            self.results_table.setItem(row, 3, QTableWidgetItem(user['city']))
            self.results_table.setItem(row, 4, QTableWidgetItem(user['postal_code']))
            
            # Add unblock button
            unblock_button = QPushButton("Unblock")
            unblock_button.clicked.connect(lambda checked, uid=user['customer_id']: 
                                         self.unblock_user(uid))
            self.results_table.setCellWidget(row, 5, unblock_button)
    
    def unblock_user(self, user_id):
        """Unblock a user"""
        if self.db_manager.update_user_status(user_id, 'active'):
            QMessageBox.information(self, "Success", f"User {user_id} has been unblocked")
            self.load_blocked_users()  # Refresh the list
        else:
            QMessageBox.warning(self, "Error", "Failed to unblock user")


class ProductListDialog(QDialog):
    """Dialog for listing and filtering products"""
    def __init__(self, db_manager, parent=None):
        super().__init__(parent)
        self.db_manager = db_manager
        self.setWindowTitle("Product List")
        self.setMinimumWidth(800)
        self.setMinimumHeight(500)
        
        layout = QVBoxLayout()
        
        # Filter controls
        filter_box = QGroupBox("Filters")
        filter_layout = QHBoxLayout()
        
        # Product type filter
        type_layout = QVBoxLayout()
        type_layout.addWidget(QLabel("Product Type:"))
        self.type_combo = QComboBox()
        self.type_combo.addItem("All", None)
        self.type_combo.addItem("Book", "Book")
        self.type_combo.addItem("Electronics", "Electronics")
        type_layout.addWidget(self.type_combo)
        filter_layout.addLayout(type_layout)
        
        # Quantity range filter
        qty_layout = QVBoxLayout()
        qty_layout.addWidget(QLabel("Quantity Range:"))
        qty_range_layout = QHBoxLayout()
        self.min_qty = QSpinBox()
        self.min_qty.setMinimum(0)
        self.min_qty.setMaximum(99999)
        self.min_qty.setSpecialValueText("Min")
        qty_range_layout.addWidget(self.min_qty)
        
        qty_range_layout.addWidget(QLabel("-"))
        
        self.max_qty = QSpinBox()
        self.max_qty.setMinimum(0)
        self.max_qty.setMaximum(99999)
        self.max_qty.setSpecialValueText("Max")
        self.max_qty.setValue(0)
        qty_range_layout.addWidget(self.max_qty)
        
        qty_layout.addLayout(qty_range_layout)
        filter_layout.addLayout(qty_layout)
        
        # Price range filter
        price_layout = QVBoxLayout()
        price_layout.addWidget(QLabel("Price Range (€):"))
        price_range_layout = QHBoxLayout()
        self.min_price = QDoubleSpinBox()
        self.min_price.setMinimum(0)
        self.min_price.setMaximum(999999)
        self.min_price.setSpecialValueText("Min")
        price_range_layout.addWidget(self.min_price)
        
        price_range_layout.addWidget(QLabel("-"))
        
        self.max_price = QDoubleSpinBox()
        self.max_price.setMinimum(0)
        self.max_price.setMaximum(999999)
        self.max_price.setSpecialValueText("Max")
        self.max_price.setValue(0)
        price_range_layout.addWidget(self.max_price)
        
        price_layout.addLayout(price_range_layout)
        filter_layout.addLayout(price_layout)
        
        filter_box.setLayout(filter_layout)
        layout.addWidget(filter_box)
        
        # Search button
        self.search_button = QPushButton("Search")
        self.search_button.clicked.connect(self.search_products)
        layout.addWidget(self.search_button)
        
        # Results table
        self.results_table = QTableWidget(0, 5)
        self.results_table.setHorizontalHeaderLabels(
            ["ID", "Type", "Description", "Price (€)", "Quantity"]
        )
        layout.addWidget(self.results_table)
        
        # Close button
        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.accept)
        layout.addWidget(self.close_button)
        
        self.setLayout(layout)
        
        # Set column resize behavior
        header = self.results_table.horizontalHeader()
        for i in range(5):
            header.setSectionResizeMode(i, QHeaderView.ResizeToContents)
    #        header.setSectionResizeMode(i, QTableWidget.resizeRowsToContents)
    
    def search_products(self):
        """Search for products with the specified filters"""
        product_type = self.type_combo.currentData()
        
        min_qty = self.min_qty.value() if self.min_qty.value() > 0 else None
        max_qty = self.max_qty.value() if self.max_qty.value() > 0 else None
        
        min_price = self.min_price.value() if self.min_price.value() > 0 else None
        max_price = self.max_price.value() if self.max_price.value() > 0 else None
        
        products = self.db_manager.get_products(
            product_type, min_qty, max_qty, min_price, max_price
        )
        
        self.display_results(products)
    
    def display_results(self, products):
        """Display search results in the table"""
        self.results_table.setRowCount(0)
        
        if not products:
            QMessageBox.information(self, "Search Results", "No products found matching the criteria")
            return
        
        for product in products:
            row = self.results_table.rowCount()
            self.results_table.insertRow(row)
            
            # Add product data
            self.results_table.setItem(row, 0, QTableWidgetItem(str(product['product_id'])))
            self.results_table.setItem(row, 1, QTableWidgetItem(product['product_type']))
            self.results_table.setItem(row, 2, QTableWidgetItem(product['description']))
            self.results_table.setItem(row, 3, QTableWidgetItem(f"{product['price']:.2f}"))
            self.results_table.setItem(row, 4, QTableWidgetItem(str(product['quantity'])))

class AddProductDialog(QDialog):
    """Dialog for adding new products"""
    def __init__(self, db_manager, parent=None):
        super().__init__(parent)
        self.db_manager = db_manager
        self.setWindowTitle("Add New Product")
        self.setMinimumWidth(500)
        
        layout = QVBoxLayout()
        
        # Product type selection
        type_layout = QHBoxLayout()
        type_layout.addWidget(QLabel("Product Type:"))
        self.product_type = QComboBox()
        self.product_type.addItem("Book")
        self.product_type.addItem("Electronics")
        self.product_type.currentIndexChanged.connect(self.toggle_product_fields)
        type_layout.addWidget(self.product_type)
        layout.addLayout(type_layout)
        
        # Common fields
        self.quantity = QSpinBox()
        self.quantity.setMinimum(1)
        self.quantity.setMaximum(9999)
        
        self.price = QDoubleSpinBox()
        self.price.setMinimum(0.01)
        self.price.setMaximum(999999.99)
        self.price.setPrefix("€ ")
        
        self.vat_rate = QDoubleSpinBox()
        self.vat_rate.setMinimum(0)
        self.vat_rate.setMaximum(100)
        self.vat_rate.setSuffix(" %")
        
        self.popularity = QSpinBox()
        self.popularity.setMinimum(1)
        self.popularity.setMaximum(5)
        
        self.image_path = QLineEdit()
        self.browse_button = QPushButton("Browse...")
        self.browse_button.clicked.connect(self.select_image)
        
        # Book fields
        self.book_fields = QWidget()
        book_layout = QFormLayout()
        self.isbn = QLineEdit()
        self.title = QLineEdit()
        self.genre = QLineEdit()
        self.publisher = QLineEdit()
        self.author = QLineEdit()
        self.publication_date = QDateEdit()
        self.publication_date.setCalendarPopup(True)
        
        book_layout.addRow("ISBN:", self.isbn)
        book_layout.addRow("Title:", self.title)
        book_layout.addRow("Genre:", self.genre)
        book_layout.addRow("Publisher:", self.publisher)
        book_layout.addRow("Author:", self.author)
        book_layout.addRow("Publication Date:", self.publication_date)
        self.book_fields.setLayout(book_layout)
        
        # Electronics fields
        self.electronics_fields = QWidget()
        electronics_layout = QFormLayout()
        self.serial_number = QLineEdit()
        self.brand = QLineEdit()
        self.model = QLineEdit()
        self.tech_specs = QTextEdit()
        self.electronics_type = QLineEdit()
        
        electronics_layout.addRow("Serial Number:", self.serial_number)
        electronics_layout.addRow("Brand:", self.brand)
        electronics_layout.addRow("Model:", self.model)
        electronics_layout.addRow("Type:", self.electronics_type)
        electronics_layout.addRow("Tech Specs:", self.tech_specs)
        self.electronics_fields.setLayout(electronics_layout)
        self.electronics_fields.hide()
        
        # Form layout for common fields
        form_layout = QFormLayout()
        form_layout.addRow("Quantity:", self.quantity)
        form_layout.addRow("Price:", self.price)
        form_layout.addRow("VAT Rate:", self.vat_rate)
        form_layout.addRow("Popularity (1-5):", self.popularity)
        form_layout.addRow("Image Path:", self.image_path)
        form_layout.addRow("", self.browse_button)
        
        # Add all to main layout
        layout.addLayout(form_layout)
        layout.addWidget(self.book_fields)
        layout.addWidget(self.electronics_fields)
        
        # Buttons
        button_layout = QHBoxLayout()
        self.add_button = QPushButton("Add Product")
        self.add_button.clicked.connect(self.add_product)
        button_layout.addWidget(self.add_button)
        
        self.cancel_button = QPushButton("Cancel")
        self.cancel_button.clicked.connect(self.reject)
        button_layout.addWidget(self.cancel_button)
        
        layout.addLayout(button_layout)
        self.setLayout(layout)
    
    def toggle_product_fields(self, index):
        """Show/hide fields based on product type selection"""
        if index == 0:  # Book
            self.book_fields.show()
            self.electronics_fields.hide()
        else:  # Electronics
            self.book_fields.hide()
            self.electronics_fields.show()
    
    def select_image(self):
        """Open file dialog to select product image"""
        file_name, _ = QFileDialog.getOpenFileName(
            self, "Select Product Image", "", "Images (*.png *.jpg *.jpeg)"
        )
        if file_name:
            self.image_path.setText(file_name)
    
    def add_product(self):
        """Add the new product to database"""
        quantity = self.quantity.value()
        price = self.price.value()
        vat_rate = self.vat_rate.value()
        popularity = self.popularity.value()
        image_path = self.image_path.text()
        
        if not image_path:
            QMessageBox.warning(self, "Input Error", "Please select an image for the product")
            return
        
        if self.product_type.currentIndex() == 0:  # Book
            isbn = self.isbn.text()
            title = self.title.text()
            genre = self.genre.text()
            publisher = self.publisher.text()
            author = self.author.text()
            pub_date = self.publication_date.date().toString("yyyy-MM-dd")
            
            if not all([isbn, title, genre, publisher, author]):
                QMessageBox.warning(self, "Input Error", "Please fill all book fields")
                return
                
            success = self.db_manager.add_book(
                quantity, price, vat_rate, popularity, image_path,
                isbn, title, genre, publisher, author, pub_date
            )
        else:  # Electronics
            serial = self.serial_number.text()
            brand = self.brand.text()
            model = self.model.text()
            tech_specs = self.tech_specs.toPlainText()
            product_type = self.electronics_type.text()
            
            if not all([serial, brand, model, product_type]):
                QMessageBox.warning(self, "Input Error", "Please fill all electronics fields")
                return
                
            success = self.db_manager.add_electronics(
                quantity, price, vat_rate, popularity, image_path,
                serial, brand, model, tech_specs, product_type
            )
        
        if success:
            QMessageBox.information(self, "Success", "Product added successfully")
            self.accept()
        else:
            QMessageBox.warning(self, "Error", "Failed to add product")

class OrderManagerDialog(QDialog):
    """Dialog for managing orders"""
    def __init__(self, db_manager, parent=None):
        super().__init__(parent)
        self.db_manager = db_manager
        self.setWindowTitle("Order Management")
        self.setMinimumWidth(800)
        self.setMinimumHeight(600)
        
        layout = QVBoxLayout()
        
        # Date selection
        date_layout = QHBoxLayout()
        date_layout.addWidget(QLabel("Select Date:"))
        self.date_edit = QDateEdit()
        self.date_edit.setDate(QDate.currentDate())
        self.date_edit.setCalendarPopup(True)
        date_layout.addWidget(self.date_edit)
        
        self.search_button = QPushButton("Search Orders")
        self.search_button.clicked.connect(self.search_orders)
        date_layout.addWidget(self.search_button)
        
        layout.addLayout(date_layout)
        
        # Orders table
        self.orders_table = QTableWidget(0, 5)
        self.orders_table.setHorizontalHeaderLabels(
            ["Order ID", "Customer", "Date", "Status", "Actions"]
        )
        self.orders_table.doubleClicked.connect(self.view_order_details)
        layout.addWidget(self.orders_table)
        
        # Close button
        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.accept)
        layout.addWidget(self.close_button)
        
        self.setLayout(layout)
        
        # Search orders for today by default
        self.search_orders()
    
    def search_orders(self):
        """Search orders for the selected date"""
        order_date = self.date_edit.date().toString("yyyy-MM-dd")
        
        cursor = self.db_manager.connection.cursor(dictionary=True)
        try:
            cursor.callproc('DailyOrders', [order_date])
            
            # Get the result set
            orders = []
            for result in cursor.stored_results():
                orders = result.fetchall()
            
            self.display_orders(orders)
        except mysql.connector.Error as err:
            QMessageBox.warning(self, "Database Error", f"Failed to retrieve orders: {err}")
        finally:
            cursor.close()
    
    def display_orders(self, orders):
        """Display orders in the table"""
        self.orders_table.setRowCount(0)
        
        if not orders:
            QMessageBox.information(self, "Search Results", "No orders found for selected date")
            return
        
        for order in orders:
            row = self.orders_table.rowCount()
            self.orders_table.insertRow(row)
            
            # Add order data
            self.orders_table.setItem(row, 0, QTableWidgetItem(str(order['order_id'])))
            self.orders_table.setItem(row, 1, QTableWidgetItem(
                f"{order['customer_id']} - {order['card_holder_name']}"
            ))
            self.orders_table.setItem(row, 2, QTableWidgetItem(
                order['order_datetime'].strftime("%Y-%m-%d %H:%M")
            ))
            self.orders_table.setItem(row, 3, QTableWidgetItem(order['status']))
            
            # Add view details button
            details_button = QPushButton("View Details")
            details_button.clicked.connect(lambda _, oid=order['order_id']: 
                                         self.view_order_details(oid))
            self.orders_table.setCellWidget(row, 4, details_button)
    
    def view_order_details(self, order_id):
        """Show details for a specific order"""
        if isinstance(order_id, int):
            # Called directly with order_id
            pass
        else:
            # Called from double-click signal
            row = self.orders_table.currentRow()
            order_id = int(self.orders_table.item(row, 0).text())
        
        dialog = OrderDetailsDialog(self.db_manager, order_id, self)
        dialog.exec()

class OrderDetailsDialog(QDialog):
    """Dialog showing order details"""
    def __init__(self, db_manager, order_id, parent=None):
        super().__init__(parent)
        self.db_manager = db_manager
        self.order_id = order_id
        self.setWindowTitle(f"Order #{order_id} Details")
        self.setMinimumWidth(600)
        
        layout = QVBoxLayout()
        
        # Order information
        info_layout = QFormLayout()
        
        cursor = self.db_manager.connection.cursor(dictionary=True)
        try:
            cursor.execute("""
                SELECT o.*, c.first_name, c.last_name, c.email
                FROM `Order` o
                JOIN Customer c ON o.customer_id = c.customer_id
                WHERE o.order_id = %s
            """, (order_id,))
            order = cursor.fetchone()
            
            if not order:
                QMessageBox.warning(self, "Error", "Order not found")
                self.reject()
                return
            
            info_layout.addRow("Order ID:", QLabel(str(order['order_id'])))
            info_layout.addRow("Customer:", QLabel(
                f"{order['first_name']} {order['last_name']} ({order['email']})"
            ))
            info_layout.addRow("Order Date:", QLabel(
                order['order_datetime'].strftime("%Y-%m-%d %H:%M:%S")
            ))
            info_layout.addRow("Status:", QLabel(order['status']))
            info_layout.addRow("Shipping Method:", QLabel(order['shipping_method']))
            info_layout.addRow("Payment Card:", QLabel(
                f"{order['card_holder_name']} (****{order['card_number'][-4:]})"
            ))
            
            # Calculate and display order total
            cursor.callproc('GetOrderTotal', [order_id, 0])
            for result in cursor.stored_results():
                total = result.fetchone()[0]
            
            info_layout.addRow("Order Total:", QLabel(f"€ {total:.2f}"))
            
        except mysql.connector.Error as err:
            QMessageBox.warning(self, "Database Error", f"Failed to retrieve order: {err}")
            self.reject()
            return
        finally:
            cursor.close()
        
        info_box = QGroupBox("Order Information")
        info_box.setLayout(info_layout)
        layout.addWidget(info_box)
        
        # Order items
        items_label = QLabel("Order Items:")
        layout.addWidget(items_label)
        
        self.items_table = QTableWidget(0, 4)
        self.items_table.setHorizontalHeaderLabels(
            ["Product ID", "Description", "Quantity", "Price"]
        )
        layout.addWidget(self.items_table)
        
        # Load order items
        self.load_order_items()
        
        # Close button
        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.accept)
        layout.addWidget(self.close_button)
        
        self.setLayout(layout)
    
    def load_order_items(self):
        """Load and display items for this order"""
        cursor = self.db_manager.connection.cursor(dictionary=True)
        try:
            cursor.execute("""
                SELECT oi.product_id, oi.quantity, p.price,
                       COALESCE(b.title, CONCAT(e.brand, ' ', e.model)) AS description
                FROM Ordered_Item oi
                JOIN Product p ON oi.product_id = p.product_id
                LEFT JOIN Book b ON p.product_id = b.product_id
                LEFT JOIN Electronics e ON p.product_id = e.product_id
                WHERE oi.order_id = %s
            """, (self.order_id,))
            
            items = cursor.fetchall()
            
            self.items_table.setRowCount(0)
            for item in items:
                row = self.items_table.rowCount()
                self.items_table.insertRow(row)
                
                self.items_table.setItem(row, 0, QTableWidgetItem(str(item['product_id'])))
                self.items_table.setItem(row, 1, QTableWidgetItem(item['description']))
                self.items_table.setItem(row, 2, QTableWidgetItem(str(item['quantity'])))
                self.items_table.setItem(row, 3, QTableWidgetItem(f"€ {item['price']:.2f}"))
                
        except mysql.connector.Error as err:
            QMessageBox.warning(self, "Database Error", f"Failed to retrieve order items: {err}")
        finally:
            cursor.close()

class MainWindow(QMainWindow):
    """Main application window"""
    def __init__(self, db_manager, operator_name):
        super().__init__()
        self.db_manager = db_manager
        self.setWindowTitle(f"BuyPy Backoffice - Welcome {operator_name}")
        self.setMinimumSize(800, 600)
        
        # Central widget and layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        layout = QVBoxLayout()
        central_widget.setLayout(layout)
        
        # Welcome label
        welcome_label = QLabel(f"Welcome, {operator_name}!")
        welcome_label.setStyleSheet("font-size: 18px; font-weight: bold;")
        layout.addWidget(welcome_label, alignment=Qt.AlignCenter)
        
        # Tab widget for different sections
        tabs = QTabWidget()
        layout.addWidget(tabs)
        


        # ADMIN Management tab
        admin_tab = QWidget()
        admin_layout = QVBoxLayout()
        admin_tab.setLayout(admin_layout)
        

        admin_buttons = QHBoxLayout()
        self.search_user_button = QPushButton("CREATE DATABASE")
        self.search_user_button.clicked.connect(self.Admin_Database_Create)
        admin_buttons.addWidget(self.search_user_button)
        admin_layout.addLayout(admin_buttons)


        # User Management tab
        user_tab = QWidget()
        user_layout = QVBoxLayout()
        user_tab.setLayout(user_layout)
        
        user_buttons = QHBoxLayout()
        self.search_user_button = QPushButton("Search User")
        self.search_user_button.clicked.connect(self.open_user_search)
        user_buttons.addWidget(self.search_user_button)
        
        self.blocked_users_button = QPushButton("View Blocked Users")
        self.blocked_users_button.clicked.connect(self.open_blocked_users)
        user_buttons.addWidget(self.blocked_users_button)
        
        user_layout.addLayout(user_buttons)
        tabs.addTab(user_tab, "User Management")
        tabs.addTab(admin_tab, "Database Management")
        
        # Product Management tab
        product_tab = QWidget()
        product_layout = QVBoxLayout()
        product_tab.setLayout(product_layout)
        
        product_buttons = QHBoxLayout()
        self.list_products_button = QPushButton("List Products")
        self.list_products_button.clicked.connect(self.open_product_list)
        product_buttons.addWidget(self.list_products_button)
        
        self.add_product_button = QPushButton("Add Product")
        self.add_product_button.clicked.connect(self.open_add_product)
        product_buttons.addWidget(self.add_product_button)
        
        product_layout.addLayout(product_buttons)
        tabs.addTab(product_tab, "Product Management")
        
        # Order Management tab
        order_tab = QWidget()
        order_layout = QVBoxLayout()
        order_tab.setLayout(order_layout)
        
        self.manage_orders_button = QPushButton("Manage Orders")
        self.manage_orders_button.clicked.connect(self.open_order_manager)
        order_layout.addWidget(self.manage_orders_button, alignment=Qt.AlignCenter)
        
        tabs.addTab(order_tab, "Order Management")
        
        # Logout button
        logout_button = QPushButton("Logout")
        logout_button.clicked.connect(self.logout)
        layout.addWidget(logout_button, alignment=Qt.AlignRight)
    
    def Admin_Database_Create(self):
        """Admin create"""
        
        msgBox = QMessageBox()
        #2025
        exec_script_mysql("BUYPY.sql", "localhost", "adminis", "ZZtopes!23", "sys")
        msgBox.setText("Base dados Criada.")
        msgBox.exec()
        #dialog = UserSearchDialog(self.db_manager, self)
        #dialog.exec()
    
    def open_user_search(self):
        """Open user search dialog"""
        dialog = UserSearchDialog(self.db_manager, self)
        dialog.exec()
    
    def open_blocked_users(self):
        """Open blocked users dialog"""
        dialog = BlockedUsersDialog(self.db_manager, self)
        dialog.exec()
    
    def open_product_list(self):
        """Open product list dialog"""
        dialog = ProductListDialog(self.db_manager, self)
        dialog.exec()
    
    def open_add_product(self):
        """Open add product dialog"""
        dialog = AddProductDialog(self.db_manager, self)
        dialog.exec()
    
    def open_order_manager(self):
        """Open order manager dialog"""
        dialog = OrderManagerDialog(self.db_manager, self)
        dialog.exec()
    
    def logout(self):
        """Logout and close the application"""
        self.db_manager.disconnect()
        self.close()

class BuyPyBackoffice:
    """Main application class"""
    def __init__(self):
        self.app = QApplication(sys.argv)
        self.config = ConfigManager()
        self.db = DatabaseManager()
        
        # Try to login with saved credentials
        username, password = self.config.load_config()
        if username and password and self.db.connect(username, password):
            self.show_main_window(username)
        else:
            self.show_login()
        
        sys.exit(self.app.exec())
    
    def show_login(self):
        """Show login dialog"""
        dialog = LoginDialog()
        if dialog.exec() == QDialog.Accepted:
            username, password = dialog.get_credentials()
            
            if self.db.connect(username, password):
                # Save credentials if login successful
                self.config.save_config(username, password)
                self.show_main_window(username)
            else:
                QMessageBox.warning(None, "Login Failed", "Invalid username or password")
                self.show_login()
    
    def show_main_window(self, username):
        """Show the main application window"""
        self.main_window = MainWindow(self.db, username)
        self.main_window.show()

if __name__ == "__main__":
    BuyPyBackoffice()