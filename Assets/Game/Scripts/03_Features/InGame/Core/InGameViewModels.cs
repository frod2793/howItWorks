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
        public event Action<List<DialogueChoiceDTO>> OnChoicesUpdated;
        public event Action<int> OnChoiceSelected;
        public event Action OnRequestBacklog;

        public bool IsTyping { get; set; }
        public bool IsDisplayingChoices { get; private set; }
        public DialogueDTO CurrentDialogue { get; private set; }

        public void DisplayDialogue(DialogueDTO dialogue)
        {
            CurrentDialogue = dialogue;
            IsDisplayingChoices = false;
            
            if (OnChoicesUpdated != null)
            {
                OnChoicesUpdated.Invoke(null);
            }

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

        public void DisplayChoices(List<DialogueChoiceDTO> choices)
        {
            IsDisplayingChoices = true;
            if (OnChoicesUpdated != null)
            {
                OnChoicesUpdated.Invoke(choices);
            }
        }

        public void SelectChoice(int choiceId)
        {
            IsDisplayingChoices = false;
            if (OnChoiceSelected != null)
            {
                OnChoiceSelected.Invoke(choiceId);
            }
            if (OnChoicesUpdated != null)
            {
                OnChoicesUpdated.Invoke(null);
            }
        }

        public void RequestBacklog()
        {
            if (OnRequestBacklog != null)
            {
                OnRequestBacklog.Invoke();
            }
        }
    }

    public class SceneInfoViewModel : ISceneInfoViewModel
    {
        public event Action<SceneInfoDTO> OnSceneInfoChanged;
        public event Action OnRequestSettings;

        public void UpdateSceneInfo(SceneInfoDTO info)
        {
            if (OnSceneInfoChanged != null)
            {
                OnSceneInfoChanged.Invoke(info);
            }
        }

        public void RequestSettings()
        {
            if (OnRequestSettings != null)
            {
                OnRequestSettings.Invoke();
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
