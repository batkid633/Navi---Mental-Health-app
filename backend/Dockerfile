# Use Python 3.11 slim image for smaller size
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies required for audio processing and ML libraries
RUN apt-get update && apt-get install -y \
    build-essential \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
# Note: Upgrade pip first for better compatibility
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    python -m nltk.downloader vader_lexicon

# Copy application code
COPY app.py .
COPY auth.py .
COPY user_data.py .
COPY whoop_api.py .
COPY sentiment/ ./sentiment/
COPY ml/ ./ml/
COPY data/ ./data/

# Create logs directory
RUN mkdir -p logs

# Expose port 8080 (Cloud Run requirement)
EXPOSE 8080

# Set environment variables
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Run FastAPI app with uvicorn
# Cloud Run requires the app to listen on 0.0.0.0 and the PORT environment variable
CMD ["sh", "-c", "exec uvicorn app:app --host 0.0.0.0 --port ${PORT} --workers 4"]
