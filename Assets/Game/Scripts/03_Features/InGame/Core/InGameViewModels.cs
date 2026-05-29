using System;
using System.Collections.Generic;
using Domain.InGame;
using UnityEngine;

namespace Features.InGame
{
    public class TopBarViewModel : ITopBarViewModel
    {
        public event Action<PlayerStatsDTO> OnStatsChanged;
        public event Action OnMenuClicked;
        public void UpdateStats(PlayerStatsDTO stats)
        {
            if (OnStatsChanged != null)
            {
                OnStatsChanged.Invoke(stats);
            }
        }
        public void ClickMenu()
        {
            if (OnMenuClicked != null)
            {
                OnMenuClicked.Invoke();
            }
        }
    }

    public class IllustrationViewModel : IIllustrationViewModel
    {
        public event Action<string> OnCharacterChanged;
        public event Action<string> OnBackgroundChanged;
        public event Action<Color> OnToneChanged;
        public void SetCharacter(string key)
        {
            if (OnCharacterChanged != null)
            {
                OnCharacterChanged.Invoke(key);
            }
        }
        public void SetBackground(string key)
        {
            if (OnBackgroundChanged != null)
            {
                OnBackgroundChanged.Invoke(key);
            }
        }
        public void SetTone(Color color)
        {
            if (OnToneChanged != null)
            {
                OnToneChanged.Invoke(color);
            }
        }
    }

    public class DialogueViewModel : IDialogueViewModel
    {
        public event Action<DialogueDTO> OnDialogueUpdated;
        public event Action OnDialogueComplete;
        public event Action OnNextRequested;

        public void DisplayDialogue(DialogueDTO dialogue)
        {
            if (OnDialogueUpdated != null)
            {
                OnDialogueUpdated.Invoke(dialogue);
            }
        }

        public void RequestNext()
        {
            if (OnNextRequested != null)
            {
                OnNextRequested.Invoke();
            }
        }

        public void NotifyComplete()
        {
            if (OnDialogueComplete != null)
            {
                OnDialogueComplete.Invoke();
            }
        }
    }

    public class ChoiceViewModel : IChoiceViewModel
    {
        public event Action<List<ChoiceDTO>> OnShowChoices;
        public event Action<int> OnChoiceSelected;

        public void ShowChoices(List<ChoiceDTO> choices)
        {
            if (OnShowChoices != null)
            {
                OnShowChoices.Invoke(choices);
            }
        }
        public void SelectChoice(int choiceId)
        {
            if (OnChoiceSelected != null)
            {
                OnChoiceSelected.Invoke(choiceId);
            }
        }
    }

    public class QuickMenuViewModel : IQuickMenuViewModel
    {
        public event Action OnSaveRequested;
        public event Action OnLoadRequested;
        public event Action OnLogRequested;
        public event Action<bool> OnAutoToggled;
        public event Action<bool> OnSkipToggled;
        public event Action OnMenuRequested;

        private bool m_isAutoOn = false;
        private bool m_isSkipOn = false;

        public void RequestSave()
        {
            if (OnSaveRequested != null)
            {
                OnSaveRequested.Invoke();
            }
        }

        public void RequestLoad()
        {
            if (OnLoadRequested != null)
            {
                OnLoadRequested.Invoke();
            }
        }

        public void RequestLog()
        {
            if (OnLogRequested != null)
            {
                OnLogRequested.Invoke();
            }
        }

        public void ClickAuto()
        {
            m_isAutoOn = !m_isAutoOn;
            if (OnAutoToggled != null)
            {
                OnAutoToggled.Invoke(m_isAutoOn);
            }
        }

        public void ClickSkip()
        {
            m_isSkipOn = !m_isSkipOn;
            if (OnSkipToggled != null)
            {
                OnSkipToggled.Invoke(m_isSkipOn);
            }
        }

        public void RequestMenu()
        {
            if (OnMenuRequested != null)
            {
                OnMenuRequested.Invoke();
            }
        }
    }

    public class EmotionPopupViewModel : IEmotionPopupViewModel
    {
        public event Action<string> OnShowEmotion;
        public void ShowEmotion(string emotionKey)
        {
            if (OnShowEmotion != null)
            {
                OnShowEmotion.Invoke(emotionKey);
            }
        }
    }

    public class UIVisibilityViewModel : IUIVisibilityViewModel
    {
        public event Action<bool> OnVisibilityChanged;
        private bool m_isVisible = true;
        public bool IsVisible
        {
            get
            {
                return m_isVisible;
            }
        }

        public void ToggleVisibility()
        {
            m_isVisible = !m_isVisible;
            if (OnVisibilityChanged != null)
            {
                OnVisibilityChanged.Invoke(m_isVisible);
            }
        }
    }
}
