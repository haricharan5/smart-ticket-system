from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential
import os


class NLPService:
    def __init__(self):
        endpoint = os.environ["AZURE_LANGUAGE_ENDPOINT"]
        key = os.environ["AZURE_LANGUAGE_KEY"]
        self.client = TextAnalyticsClient(
            endpoint=endpoint,
            credential=AzureKeyCredential(key)
        )

    def analyze_sentiment(self, text: str) -> dict:
        response = self.client.analyze_sentiment([text[:5000]])[0]
        negative_score = response.confidence_scores.negative
        sentiment = response.sentiment

        if sentiment == "positive":
            urgency = "Low"
        elif sentiment == "neutral":
            urgency = "Low"
        elif negative_score < 0.5:
            urgency = "Medium"
        elif negative_score < 0.75:
            urgency = "High"
        else:
            urgency = "Critical"

        return {
            "sentiment": sentiment,
            "urgency": urgency,
            "negative_score": negative_score,
        }
