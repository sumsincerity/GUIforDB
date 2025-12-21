import bcrypt
pwd = input()
hashed = bcrypt.hashpw(pwd.encode('utf-8'), bcrypt.gensalt(rounds=12))
print(hashed.decode('utf-8'))
