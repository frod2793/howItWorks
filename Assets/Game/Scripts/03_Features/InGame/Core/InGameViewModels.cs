using System;
using System.Collections.Generic;
using Domain.InGame;
using UnityEngine;

namespace Features.InGame
{
    public class DialogueViewModel : IDialogueViewModel
    {
        public event Action<DialogueDTO> OnDialogueUpdated;
        public event Action OnDialogueComplete;
        public event Action OnNextRequested;
        public event Action OnSkipRequested;

        public bool IsTyping { get; set; }

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

        public void RequestSkip()
        {
            if (OnSkipRequested != null)
            {
                OnSkipRequested.Invoke();
            }
        }
    }

    public class SceneInfoViewModel : ISceneInfoViewModel
    {
        public event Action<SceneInfoDTO> OnSceneInfoChanged;

        public void UpdateSceneInfo(SceneInfoDTO info)
        {
            if (OnSceneInfoChanged != null)
            {
                OnSceneInfoChanged.Invoke(info);
            }
        }
    }

    public class SidePanelViewModel : ISidePanelViewModel
    {
        public event Action<SidePanelDTO> OnSidePanelDataChanged;

        public void UpdateSidePanelData(SidePanelDTO data)
        {
            if (OnSidePanelDataChanged != null)
            {
                OnSidePanelDataChanged.Invoke(data);
            }
        }
    }
}
