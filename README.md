# Navi---Mental-Health-app

The idea is to have a fully integrated mental health companion app, that gives feedback and potential treatment options to a lisenced psychologist

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

  - late stage fusion ML model that outputs one deression and anxiety score from combined:
    - linear model assessing text entries (trained on reddit/subreddits)
    - random forest assesing audio files (trained on DAIC-WOZ)
    - 




