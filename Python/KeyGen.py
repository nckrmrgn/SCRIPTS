import random
import string

def generate_code(length=50):
    if length < 4:
        raise ValueError("length must be at least 4 to include all required character types")

    chars = string.ascii_letters + string.digits + '.-'

    # Guarantee one of each required type
    required = [
        random.choice(string.ascii_uppercase),
        random.choice(string.ascii_lowercase),
        '.',
        '-',
    ]

    # Fill the rest randomly
    remaining = [random.choice(chars) for _ in range(length - len(required))]

    result = required + remaining
    random.shuffle(result)
    return ''.join(result)

code = generate_code()
print(code)