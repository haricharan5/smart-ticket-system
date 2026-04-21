"""
Generates 500 synthetic support tickets across 5 categories.
Run: python generate_dataset.py
Output: tickets.json (used by seed.py to populate Azure SQL)
"""
import json
import random

CATEGORIES = {
    "Technical Issue": [
        ("Login page returns 500 error", "I cannot log into the system. The page shows Internal Server Error since this morning. I've cleared cache and tried different browsers."),
        ("VPN connection drops every 10 minutes", "Our VPN disconnects frequently during video calls, affecting our entire team's productivity. This started after the last system update."),
        ("Email client not syncing", "Outlook stopped syncing emails 2 days ago. I've tried removing and re-adding the account but the issue persists."),
        ("Printer not recognized after Windows update", "After last Tuesday's Windows update, my printer no longer appears as an available device. Other team members have the same issue."),
        ("Database backup failing with timeout error", "The nightly database backup job is failing with a timeout error. We haven't had a successful backup in 3 days."),
        ("Application crashes on launch", "The CRM application crashes immediately upon opening. I see a crash report mentioning memory access violation."),
        ("Slow internet speed on 3rd floor", "The WiFi on the 3rd floor is extremely slow — around 2 Mbps vs the usual 100 Mbps. Other floors seem fine."),
        ("Two-factor authentication not working", "I'm not receiving the 2FA code via SMS. I've verified my phone number is correct in the system."),
        ("File server inaccessible from remote work", "I cannot access the company file server when working from home, even with VPN connected."),
        ("Software license expired", "The Adobe Creative Suite license expired and I'm unable to continue work on the current design project."),
    ],
    "Billing Query": [
        ("Double charged for last month subscription", "I was charged twice on my credit card for the April subscription. Transaction IDs: TXN-4421 and TXN-4422. Please refund one."),
        ("Invoice missing company VAT number", "The invoice I received for order #INV-2024-089 is missing our VAT registration number. I need this for accounting."),
        ("Request for refund on cancelled order", "I cancelled order #ORD-7731 within the 48-hour window but haven't received a refund after 10 days."),
        ("Subscription plan downgrade not reflected", "I downgraded from Premium to Basic plan 2 weeks ago but I'm still being charged the Premium rate."),
        ("Payment method update required", "My credit card expired. I need to update payment details but the portal isn't accepting my new card number."),
        ("Annual invoice request", "Could you please send me an annual summary invoice for all 2023 transactions? I need this for our tax filing."),
        ("Unexpected charge on account", "There's an unrecognized charge of $89.99 on my account dated March 15. I did not authorize this transaction."),
        ("Discount code not applied", "I used promo code SAVE20 at checkout but the 20% discount wasn't applied to my order. Order number: #ORD-9981."),
        ("Early cancellation fee dispute", "I was charged a $150 early cancellation fee but my contract clearly states cancellation is free after 6 months."),
        ("Payment plan request for large invoice", "I received invoice #INV-2024-112 for $4,500. Can we arrange a payment plan over 3 months?"),
    ],
    "General Inquiry": [
        ("How to export data to Excel", "Could you guide me on how to export my project data to an Excel file? I've looked through the settings but can't find the option."),
        ("Request for product demo", "Our team is interested in upgrading to the Enterprise plan. Could you arrange a product demo with our sales team?"),
        ("API documentation request", "I'm looking for the API documentation to integrate your service with our internal system. Where can I find this?"),
        ("Office hours query", "What are the support team's operating hours? I need to know when I can reach someone for urgent issues."),
        ("Feature request: dark mode", "Many of our team members work late and would greatly benefit from a dark mode option in the application."),
        ("How to set up team permissions", "I need to give different access levels to different team members. Can you walk me through the permissions settings?"),
        ("Training material request", "We have 5 new employees joining next week. Do you have any training videos or documentation we can share with them?"),
        ("Data retention policy question", "How long do you retain our data after account cancellation? We need this information for our compliance documentation."),
        ("Request for SLA documentation", "Could you send us your official SLA document? Our procurement team needs it for the vendor approval process."),
        ("Mobile app availability", "Is there a mobile app available for iOS and Android? Some of our field team members need access while travelling."),
    ],
    "HR/Internal": [
        ("Leave balance discrepancy", "My leave balance shows 3 days remaining but according to my calculation I should have 8 days. Please review."),
        ("Payslip not generated for March", "I did not receive my payslip for March 2024. My colleagues received theirs on the 28th but I haven't received mine."),
        ("Work from home equipment request", "I need a second monitor and an ergonomic chair for my home office setup. Please let me know the approval process."),
        ("Access badge not working", "My office access badge stopped working this morning. I cannot enter the building and have an important meeting at 10 AM."),
        ("Team lunch expense reimbursement", "I paid for the team lunch on April 10th (receipt attached, $245). Please process the reimbursement to my account."),
        ("Health insurance card replacement", "My health insurance card was lost. I need a replacement card before my doctor's appointment next week."),
        ("Parking pass renewal", "My monthly parking pass expires at end of April. Please renew it for another 6 months."),
        ("Training budget approval", "I'd like to attend the Azure certification training ($800). Could you approve this from the training budget?"),
        ("Contract renewal query", "My 1-year contract ends on May 30th. I'd like to know if it will be renewed and when I can expect confirmation."),
        ("Relocation assistance request", "I've been asked to relocate to the London office. Can you provide information about the relocation assistance policy?"),
    ],
    "Other": [
        ("Website feedback", "I wanted to share some feedback on the new website design. The navigation is confusing and I had difficulty finding the contact page."),
        ("Partnership inquiry", "Our company is interested in exploring a partnership opportunity. Who should I contact to discuss this further?"),
        ("Press and media inquiry", "I'm a journalist writing an article about cloud services. Could you connect me with your communications team?"),
        ("General complaint about service", "I've had multiple unresolved issues over the past month and I'm very frustrated with the overall support experience."),
        ("Suggestion for improvement", "The ticket submission form could be improved by adding file attachment support. This would help us provide more context."),
        ("Wrong department contact", "I think this query was sent to the wrong team. I'm looking for information about your physical office locations."),
        ("Thank you note", "I just wanted to say thank you to John from the support team who went above and beyond to resolve my issue yesterday."),
        ("Survey response submission", "I'm responding to the customer satisfaction survey you sent last week. Overall my experience has been positive."),
        ("Old ticket follow-up", "I submitted ticket #1234 three weeks ago and it was marked resolved, but the issue has come back. Can you reopen it?"),
        ("General question about company", "Could you tell me more about your company's environmental sustainability policies? We factor this into our vendor selection."),
    ],
}

SENTIMENTS = ["positive", "neutral", "negative", "negative", "negative"]
EMAILS = [
    "john.smith@acme.com", "sarah.jones@techcorp.com", "mike.patel@globalinc.com",
    "emily.chen@startupco.com", "david.brown@enterprise.org", "lisa.wilson@midsize.net",
    "james.taylor@corp.com", "anna.martinez@business.io", "robert.lee@company.com",
    "sophie.white@firm.co",
]


def generate():
    tickets = []
    for category, examples in CATEGORIES.items():
        for _ in range(100):
            title, description = random.choice(examples)
            # Add slight variation
            variation_prefix = random.choice(["URGENT: ", "Follow-up: ", "", "", ""])
            tickets.append({
                "title": variation_prefix + title,
                "description": description,
                "submitter_email": random.choice(EMAILS),
                "expected_category": category,
            })
    random.shuffle(tickets)
    with open("tickets.json", "w") as f:
        json.dump(tickets, f, indent=2)
    print(f"Generated {len(tickets)} tickets → tickets.json")


if __name__ == "__main__":
    generate()
