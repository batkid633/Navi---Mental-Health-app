# Navi---Mental-Health-app

The idea is to have a fully integrated mental health companion app, that gives feedback and potential treatment options to a lisenced psychologist. Provides a working application/product that integrates multimodal depression analysis with a dataset backed treatment prediction


CURRENT MODEL:

A journaling feature that assesses text and evaluates a depression score. logs scores in a .csv
  - linear model trained on Reddit Mental Health Dataset

With that score and other physiological info, a trained model would output treatment options that are most likely to fit your lifestyle and depression type
  - random forest model trained on simulated STAR*D dataset


END GOAL:

A depression and anxiety score tracker based on multiple factors
  - journal entries 
  - audio files/recordings
  - lifestlye and physical attributes (itegrated from a fitness tracker)
  - *possible keyboard/typing behavior tracking

  - late stage fusion ML model that outputs one depression and anxiety score from combined:
    - linear model assessing text entries (trained on reddit/subreddits)
    - random forest assesing audio files (trained on DAIC-WOZ)
    - gradient boosting assessing physio data (DAIC-WOZ?)

A predicted best possible treatment section
  - ML model (forrest?) trained on STAR*D dataset
    - uses depression score and physio input, outputs best possible treatment course based on STAR*D dataset

TO DO:

  - add storage and simple security for testing (only inputting my data so far)
  - prepare datasets/remove identifying info (DAIC-WOZ and STAR*D) for integration into pipeline
  - incorporate physio data from third party source with consent
  - train models and store artifacts
  - add stronger encryption for future users
  - mobile and full web UI
  



