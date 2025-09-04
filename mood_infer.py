import numpy as np

def predict_mood(texts, model, vectorizer, classes):
    X = vectorizer.transform(texts).toarray()
    probs = model.predict(X, verbose=0)
    idxs = probs.argmax(axis=1)
    labels = [classes[i] for i in idxs]
    return probs, labels