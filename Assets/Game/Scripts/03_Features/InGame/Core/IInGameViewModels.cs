using System;
using System.Collections.Generic;
using Domain.InGame;
using UnityEngine;

namespace Features.InGame
{
    public interface IDialogueViewModel
    {
        event Action<DialogueDTO> OnDialogueUpdated;
        event Action OnDialogueComplete;
        event Action OnNextRequested;
        event Action OnSkipRequested;
        event Action<List<DialogueChoiceDTO>> OnChoicesUpdated;
        event Action<int> OnChoiceSelected;
        event Action OnRequestBacklog;
        bool IsTyping { get; set; }
        bool IsDisplayingChoices { get; }
        DialogueDTO CurrentDialogue { get; }
        void DisplayDialogue(DialogueDTO dialogue);
        void RequestNext();
        void NotifyComplete();
        void RequestSkip();
        void DisplayChoices(List<DialogueChoiceDTO> choices);
        void SelectChoice(int choiceId);
        void RequestBacklog();
    }

    public interface ISceneInfoViewModel
    {
        event Action<SceneInfoDTO> OnSceneInfoChanged;
        event Action OnSceneInfoUpdated;
        event Action OnRequestSettings;
        string DisplaySceneTitle { get; }
        string DisplayLocation { get; }
        string DisplayPlaythrough { get; }
        void UpdateSceneInfo(SceneInfoDTO info);
        void RequestSettings();
    }

    public interface ISidePanelViewModel
    {
        event Action<SidePanelDTO> OnSidePanelDataChanged;
        void UpdateSidePanelData(SidePanelDTO data);
    }
}
