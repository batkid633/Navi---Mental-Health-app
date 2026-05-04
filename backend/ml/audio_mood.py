import librosa
import numpy as np
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
import joblib
import os
from pathlib import Path
import pandas as pd

class AudioMoodAnalyzer:
    def __init__(self, model_path=None):
        self.scaler = StandardScaler()
        self.model = RandomForestClassifier(n_estimators=100, random_state=42)
        self.model_path = model_path or Path(__file__).parent / "models" / "audio_mood_model.pkl"
        self.scaler_path = Path(__file__).parent / "models" / "audio_scaler.pkl"

        # Ensure models directory exists
        self.model_path.parent.mkdir(exist_ok=True)

    def extract_mfcc_features(self, audio_path, n_mfcc=13, max_length=300):
        """Extract MFCC features from audio file"""
        try:
            # Load audio file
            y, sr = librosa.load(audio_path, sr=22050)

            # Extract MFCCs
            mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)

            # Extract additional features
            chroma = librosa.feature.chroma_stft(y=y, sr=sr)
            spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
            spectral_rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)
            zero_crossing_rate = librosa.feature.zero_crossing_rate(y)
            rms = librosa.feature.rms(y=y)

            # Combine features
            features = np.concatenate([
                np.mean(mfccs, axis=1),
                np.std(mfccs, axis=1),
                np.mean(chroma, axis=1),
                np.std(chroma, axis=1),
                np.mean(spectral_centroid),
                np.std(spectral_centroid),
                np.mean(spectral_rolloff),
                np.std(spectral_rolloff),
                np.mean(zero_crossing_rate),
                np.std(zero_crossing_rate),
                np.mean(rms),
                np.std(rms)
            ])

            return features

        except Exception as e:
            print(f"Error extracting features from {audio_path}: {e}")
            return None

    def train_model(self, training_data_path):
        """Train the mood classification model"""
        if not os.path.exists(training_data_path):
            print(f"Training data not found: {training_data_path}")
            return False

        # Load training data (CSV with audio_path and mood_label columns)
        df = pd.read_csv(training_data_path)

        features_list = []
        labels = []

        for _, row in df.iterrows():
            audio_path = row['audio_path']
            mood_label = row['mood_label']

            if os.path.exists(audio_path):
                features = self.extract_mfcc_features(audio_path)
                if features is not None:
                    features_list.append(features)
                    labels.append(mood_label)

        if not features_list:
            print("No valid audio features extracted for training")
            return False

        X = np.array(features_list)
        y = np.array(labels)

        # Scale features
        X_scaled = self.scaler.fit_transform(X)

        # Train model
        self.model.fit(X_scaled, y)

        # Save model and scaler
        joblib.dump(self.model, self.model_path)
        joblib.dump(self.scaler, self.scaler_path)

        print(f"Model trained with {len(features_list)} samples")
        return True

    def load_model(self):
        """Load trained model and scaler"""
        try:
            if os.path.exists(self.model_path) and os.path.exists(self.scaler_path):
                self.model = joblib.load(self.model_path)
                self.scaler = joblib.load(self.scaler_path)
                return True
            else:
                print("Model files not found")
                return False
        except Exception as e:
            print(f"Error loading model: {e}")
            return False

    def predict_mood(self, audio_path):
        """Predict mood from audio file"""
        if not self.load_model():
            return {"error": "Model not trained or loaded"}

        features = self.extract_mfcc_features(audio_path)
        if features is None:
            return {"error": "Could not extract features from audio"}

        # Scale features
        features_scaled = self.scaler.transform([features])

        # Predict
        prediction = self.model.predict(features_scaled)[0]
        probabilities = self.model.predict_proba(features_scaled)[0]

        # Get mood labels
        mood_labels = self.model.classes_

        # Create response
        result = {
            "predicted_mood": prediction,
            "confidence": float(probabilities[np.argmax(probabilities)]),
            "probabilities": {
                mood: float(prob) for mood, prob in zip(mood_labels, probabilities)
            }
        }

        return result

    def analyze_audio_file(self, audio_path):
        """Comprehensive audio analysis"""
        if not os.path.exists(audio_path):
            return {"error": "Audio file not found"}

        try:
            # Load audio
            y, sr = librosa.load(audio_path, sr=22050)

            # Basic audio features
            duration = len(y) / sr
            rms = np.sqrt(np.mean(y**2))

            # Pitch analysis
            pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
            pitch_mean = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

            # Tempo
            tempo, _ = librosa.beat.tempo(y=y, sr=sr)

            # Spectral features
            spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
            spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))

            analysis = {
                "duration_seconds": float(duration),
                "rms_energy": float(rms),
                "mean_pitch_hz": float(pitch_mean),
                "tempo_bpm": float(tempo),
                "spectral_centroid": float(spectral_centroid),
                "spectral_rolloff": float(spectral_rolloff)
            }

            return analysis

        except Exception as e:
            return {"error": f"Analysis failed: {str(e)}"}

def generate_emotional_intervention(mood_result):
    """Generate emotional support intervention based on mood analysis"""
    if not mood_result or 'predicted_mood' not in mood_result:
        return {"suggestions": ["Take a moment to breathe and reflect on your feelings."]}
    
    mood = mood_result['predicted_mood'].lower()
    
    interventions = {
        'sad': [
            "Consider reaching out to a friend or loved one",
            "Try a short walk in nature",
            "Write down three things you're grateful for",
            "Listen to uplifting music or a favorite podcast"
        ],
        'angry': [
            "Try deep breathing exercises: inhale for 4 counts, hold for 4, exhale for 4",
            "Physical activity can help release tension - consider a brisk walk",
            "Write down what's bothering you, then set it aside",
            "Practice progressive muscle relaxation"
        ],
        'anxious': [
            "Ground yourself: name 5 things you can see, 4 you can touch, 3 you can hear, 2 you can smell, 1 you can taste",
            "Try the 4-7-8 breathing technique",
            "Break down overwhelming thoughts into smaller, manageable pieces",
            "Consider a short meditation or mindfulness exercise"
        ],
        'happy': [
            "Celebrate this positive moment!",
            "Consider sharing your joy with someone you care about",
            "Take a moment to savor this feeling",
            "Use this energy for something meaningful"
        ]
    }
    
    return {
        "mood": mood,
        "suggestions": interventions.get(mood, ["Take care of yourself today."])
    }

def analyze_mfcc_deep(audio_path):
    """Perform deep MFCC analysis for structured assessment"""
    if not os.path.exists(audio_path):
        return {"error": "Audio file not found"}

    try:
        # Load audio
        y, sr = librosa.load(audio_path, sr=22050)
        
        # Extract detailed MFCCs
        mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=40, n_fft=2048, hop_length=512)
        
        # Statistical features
        mfcc_stats = {
            "mean": np.mean(mfccs, axis=1).tolist(),
            "std": np.std(mfccs, axis=1).tolist(),
            "min": np.min(mfccs, axis=1).tolist(),
            "max": np.max(mfccs, axis=1).tolist(),
            "median": np.median(mfccs, axis=1).tolist()
        }
        
        # Spectral features
        spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
        spectral_rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)
        spectral_bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)
        
        spectral_stats = {
            "centroid_mean": float(np.mean(spectral_centroid)),
            "centroid_std": float(np.std(spectral_centroid)),
            "rolloff_mean": float(np.mean(spectral_rolloff)),
            "rolloff_std": float(np.std(spectral_rolloff)),
            "bandwidth_mean": float(np.mean(spectral_bandwidth)),
            "bandwidth_std": float(np.std(spectral_bandwidth))
        }
        
        # Chroma features
        chroma = librosa.feature.chroma_stft(y=y, sr=sr)
        chroma_stats = {
            "chroma_mean": np.mean(chroma, axis=1).tolist(),
            "chroma_std": np.std(chroma, axis=1).tolist()
        }
        
        # Rhythm features
        tempo, beat_positions = librosa.beat.tempo(y=y, sr=sr, onset_envelope=None)
        beat_strength = librosa.feature.rms(y=y)
        
        rhythm_stats = {
            "tempo": float(tempo),
            "beat_strength_mean": float(np.mean(beat_strength)),
            "beat_strength_std": float(np.std(beat_strength))
        }
        
        return {
            "mfcc_statistics": mfcc_stats,
            "spectral_features": spectral_stats,
            "chroma_features": chroma_stats,
            "rhythm_features": rhythm_stats,
            "duration_seconds": float(len(y) / sr)
        }

    except Exception as e:
        return {"error": f"Deep MFCC analysis failed: {str(e)}"}

# Global analyzer instance
analyzer = AudioMoodAnalyzer()

def extract_audio_features(audio_path):
    """Extract MFCC and other features for mood analysis"""
    return analyzer.extract_mfcc_features(audio_path)

def predict_audio_mood(audio_path):
    """Predict mood from audio file"""
    return analyzer.predict_mood(audio_path)

def analyze_audio_comprehensive(audio_path):
    """Get comprehensive audio analysis"""
    return analyzer.analyze_audio_file(audio_path)

def train_audio_mood_model(training_csv_path):
    """Train the audio mood classification model"""
    return analyzer.train_model(training_csv_path)