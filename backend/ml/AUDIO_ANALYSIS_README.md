# Audio Mood Analysis

This module provides MFCC-based audio feature extraction and mood classification for voice recordings.

## Features

- **MFCC Extraction**: 13 MFCC coefficients + deltas + additional spectral features
- **Mood Classification**: Random Forest classifier trained on audio features
- **Real-time Analysis**: Process uploaded audio files via REST API
- **Comprehensive Metrics**: Duration, tempo, spectral centroid, RMS energy, etc.

## API Endpoints

### POST /audio/analyze
Upload an audio file for mood analysis.

**Request**: Multipart form with `file` field (WAV format recommended)
**Response**:
```json
{
  "filename": "recording.wav",
  "mood_analysis": {
    "predicted_mood": "happy",
    "confidence": 0.85,
    "probabilities": {
      "happy": 0.85,
      "sad": 0.10,
      "calm": 0.05
    }
  },
  "audio_features": {
    "duration_seconds": 12.3,
    "rms_energy": 0.123,
    "mean_pitch_hz": 185.5,
    "tempo_bpm": 120.0,
    "spectral_centroid": 2500.0,
    "spectral_rolloff": 4000.0
  }
}
```

### POST /audio/train
Train the mood classification model.

**Request**:
```json
{
  "training_csv_path": "/path/to/training/data.csv"
}
```

## Training Data Format

CSV file with columns:
- `audio_path`: Full path to audio file
- `mood_label`: Mood class (happy, sad, calm, anxious, etc.)

Example:
```csv
audio_path,mood_label
/data/audio/happy1.wav,happy
/data/audio/sad1.wav,sad
/data/audio/calm1.wav,calm
```

## Audio Requirements

- **Format**: WAV (16-bit, 44.1kHz or 22.05kHz)
- **Length**: 3-30 seconds optimal
- **Quality**: Clear voice recordings
- **Sample Rate**: 22050 Hz (automatically resampled if different)

## Feature Extraction

The system extracts:
- 13 MFCC coefficients (mean + std)
- Chroma features (12 bins, mean + std)
- Spectral centroid and rolloff
- Zero-crossing rate
- RMS energy
- Fundamental frequency (pitch)

Total: ~40 features per audio sample

## Model Training

```python
from ml.audio_mood import train_audio_mood_model

# Train model
success = train_audio_mood_model("path/to/training.csv")
```

## Usage in Flutter App

```dart
import 'services/audio_analysis_service.dart';

// Analyze recorded audio
final analysis = await AudioAnalysisService.analyzeAudio(audioFile);
print("Predicted mood: ${analysis['mood_analysis']['predicted_mood']}");
```

## Dependencies

- librosa: Audio processing
- numpy: Numerical computations
- scikit-learn: ML classification
- scipy: Signal processing

Install with: `pip install -r requirements.txt`