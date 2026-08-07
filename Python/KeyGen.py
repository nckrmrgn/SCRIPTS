import random
import string

def generate_code(length=50):
    chars = string.ascii_letters + string.digits + '.-'
    return ''.join(random.choice(chars) for _ in range(length))

code = generate_code()
print(code)