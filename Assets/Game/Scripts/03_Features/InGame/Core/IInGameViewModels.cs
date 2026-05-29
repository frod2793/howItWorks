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
        bool IsTyping { get; set; }
        void DisplayDialogue(DialogueDTO dialogue);
        void RequestNext();
        void NotifyComplete();
        void RequestSkip();
    }

    public interface ISceneInfoViewModel
    {
        event Action<SceneInfoDTO> OnSceneInfoChanged;
        void UpdateSceneInfo(SceneInfoDTO info);
    }

    public interface ISidePanelViewModel
    {
        event Action<SidePanelDTO> OnSidePanelDataChanged;
        void UpdateSidePanelData(SidePanelDTO data);
    }
}
