using System;
using System.Collections.Generic;
using Domain.InGame;
using UnityEngine;

namespace Features.InGame
{
    public interface ITopBarViewModel
    {
        event Action<PlayerStatsDTO> OnStatsChanged;
        event Action OnMenuClicked;
        void UpdateStats(PlayerStatsDTO stats);
        void ClickMenu();
    }

    public interface IIllustrationViewModel
    {
        event Action<string> OnCharacterChanged;
        event Action<string> OnBackgroundChanged;
        event Action<Color> OnToneChanged;
        void SetCharacter(string key);
        void SetBackground(string key);
        void SetTone(Color color);
    }

    public interface IDialogueViewModel
    {
        event Action<DialogueDTO> OnDialogueUpdated;
        event Action OnDialogueComplete;
        void DisplayDialogue(DialogueDTO dialogue);
        void RequestNext();
    }

    public interface IChoiceViewModel
    {
        event Action<List<ChoiceDTO>> OnShowChoices;
        event Action<int> OnChoiceSelected;
        void ShowChoices(List<ChoiceDTO> choices);
        void SelectChoice(int choiceId);
    }

    public interface IQuickMenuViewModel
    {
        event Action OnSaveRequested;
        event Action OnLoadRequested;
        event Action OnLogRequested;
        event Action<bool> OnAutoToggled;
        event Action<bool> OnSkipToggled;
        event Action OnMenuRequested;

        void RequestSave();
        void RequestLoad();
        void RequestLog();
        void ClickAuto();
        void ClickSkip();
        void RequestMenu();
    }

    public interface IEmotionPopupViewModel
    {
        event Action<string> OnShowEmotion;
        void ShowEmotion(string emotionKey);
    }

    public interface IUIVisibilityViewModel
    {
        event Action<bool> OnVisibilityChanged;
        bool IsVisible { get; }
        void ToggleVisibility();
    }
}
