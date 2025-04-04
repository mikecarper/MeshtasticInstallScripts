#!/usr/bin/env python3

def main():
    # Prompt for input: amount and optional split count.
    user_input = input("Enter bill amount and optional split count (e.g., '44.56' or '44.56 3'): ").strip()
    if not user_input:
        print("No input provided.")
        return

    tokens = user_input.split()
    try:
        # First token is the bill amount.
        amount = float(tokens[0])
    except ValueError:
        print("Invalid bill amount.")
        return

    # Second token (optional) is the number of splits.
    if len(tokens) >= 2:
        try:
            split_count = int(tokens[1])
            if split_count <= 0:
                print("Split count must be a positive integer.")
                return
        except ValueError:
            print("Invalid split count. Must be an integer.")
            return
    else:
        split_count = 1  # default: no split

    # Calculate per-person bill.
    per_person = amount / split_count

    # Define tip percentages.
    tip_percentages = [5, 10, 15, 18, 20, 25, 30]

    # Display summary.
    print(f"\nBill Amount: ${amount:.2f}")
    if split_count > 1:
        print(f"Split {split_count} ways: ${per_person:.2f} per person")
    else:
        print("No bill splitting.")

    print("\nTip Options (per person):")
    for tip in tip_percentages:
        tip_amount = per_person * (tip / 100)
        total = per_person + tip_amount
        print(f"{tip}% tip: Tip = ${tip_amount:.2f}, Total = ${total:.2f}")

if __name__ == '__main__':
    main()
