using System;
using System.Collections.Generic;
using Domain.InGame;
using UnityEngine;

namespace Features.InGame
{
    public class BacklogViewModel : IBacklogViewModel, IDisposable
    {
        private readonly IDialogueViewModel m_dialogueVM;
        private readonly ISceneInfoViewModel m_sceneInfoVM;
        private readonly IGameDataManager m_dataManager;
        private readonly List<BacklogItemDTO> m_items = new List<BacklogItemDTO>();
        private string m_currentSceneInfoText = string.Empty;

        public event Action OnBacklogUpdated;
        public event Action<int> OnRequestJump;

        public IReadOnlyList<BacklogItemDTO> Items
        {
            get
            {
                return m_items;
            }
        }

        public string CurrentSceneInfo
        {
            get
            {
                return m_currentSceneInfoText;
            }
        }

        public BacklogViewModel(
            IDialogueViewModel dialogueVM,
            ISceneInfoViewModel sceneInfoVM,
            IGameDataManager dataManager)
        {
            m_dialogueVM = dialogueVM;
            m_sceneInfoVM = sceneInfoVM;
            m_dataManager = dataManager;

            if (m_dialogueVM != null)
            {
                m_dialogueVM.OnDialogueUpdated += HandleDialogueUpdated;
            }
            if (m_sceneInfoVM != null)
            {
                m_sceneInfoVM.OnSceneInfoChanged += HandleSceneInfoChanged;
            }
        }

        public void Clear()
        {
            m_items.Clear();
            if (OnBacklogUpdated != null)
            {
                OnBacklogUpdated.Invoke();
            }
        }

        private void HandleDialogueUpdated(DialogueDTO dialogue)
        {
            if (dialogue == null || string.IsNullOrEmpty(dialogue.Content))
            {
                return;
            }

            bool hasBranchEffect = false;
            if (m_dataManager != null)
            {
                var triggers = m_dataManager.GetChoiceTriggers();
                if (triggers != null)
                {
                    for (int i = 0; i < triggers.Count; i++)
                    {
                        if (triggers[i].TriggerDialogueIndex == dialogue.CurrentLine - 1)
                        {
                            hasBranchEffect = true;
                            break;
                        }
                    }
                }
            }

            m_items.Add(new BacklogItemDTO
            {
                SpeakerName = dialogue.SpeakerName,
                Content = dialogue.Content,
                SpeakerIconKey = dialogue.SpeakerIconKey,
                Type = dialogue.Type,
                HasBranchEffect = hasBranchEffect,
                DialogueIndex = dialogue.CurrentLine - 1
            });

            if (OnBacklogUpdated != null)
            {
                OnBacklogUpdated.Invoke();
            }
        }

        public void JumpToLine(int dialogueIndex)
        {
            if (OnRequestJump != null)
            {
                OnRequestJump.Invoke(dialogueIndex);
            }
        }

        private void HandleSceneInfoChanged(SceneInfoDTO info)
        {
            if (info != null)
            {
                m_currentSceneInfoText = $"현재 씬: {info.ActName} · 씬 {info.SceneNumber} — {info.SceneTitle}";
            }
        }

        public void Dispose()
        {
            if (m_dialogueVM != null)
            {
                m_dialogueVM.OnDialogueUpdated -= HandleDialogueUpdated;
            }
            if (m_sceneInfoVM != null)
            {
                m_sceneInfoVM.OnSceneInfoChanged -= HandleSceneInfoChanged;
            }
        }
    }
}
