using Cysharp.Threading.Tasks;
using System.Collections.Generic;
using Domain.InGame;
using UnityEngine;

namespace Features.InGame
{
    public class DialogueFlowController
    {
        private readonly IDialogueViewModel m_dialogueVM;
        private readonly ISceneInfoViewModel m_sceneInfoVM;
        private readonly ISidePanelViewModel m_sidePanelVM;
        private readonly IGameDataManager m_dataManager;
        private List<Domain.InGame.DialogueLineDTO> m_loadedDialogues;
        private int m_currentDialogueIndex = 0;

        public DialogueFlowController(
            IDialogueViewModel dialogueVM, 
            ISceneInfoViewModel sceneInfoVM, 
            ISidePanelViewModel sidePanelVM, 
            IGameDataManager dataManager)
        {
            m_dialogueVM = dialogueVM;
            m_sceneInfoVM = sceneInfoVM;
            m_sidePanelVM = sidePanelVM;
            m_dataManager = dataManager;
            m_dialogueVM.OnNextRequested += PlayNextDialogue;
        }

        public async UniTaskVoid StartDialogueFlowAsync()
        {
            m_sceneInfoVM.UpdateSceneInfo(new SceneInfoDTO
            {
                ActName = "승(承)",
                SceneNumber = 8,
                SceneTitle = "카토 위기",
                Location = "야만인 구역 외곽",
                TimeOfDay = "밤",
                Playthrough = 1
            });

            m_sidePanelVM.UpdateSidePanelData(new SidePanelDTO
            {
                TrustStocks = 2,
                MaxTrustStocks = 5,
                Sadness = 6,
                Joy = 1,
                Curiosity = 7,
                Fear = 3,
                Confusion = 3,
                Monitoring = 5,
                Trust = 4,
                LoopAwareness = 1,
                MaxLoopAwareness = 5,
                ActBranchInfo = "D1 · R · V · β",
                PassedScenesInfo = "씬 2 · 3 · 5 · 7"
            });

            await m_dataManager.LoadAllDataAsync();
            m_loadedDialogues = m_dataManager.GetDialogueLog();
            m_currentDialogueIndex = 0;

            if (m_loadedDialogues != null && m_loadedDialogues.Count > 0)
            {
                PlayDialogueAtIndex(m_currentDialogueIndex);
            }
            else
            {
                m_dialogueVM.DisplayDialogue(new DialogueDTO
                {
                    Type = DialogueType.Normal,
                    SpeakerName = "시스템",
                    Content = "불러올 다이얼로그 데이터가 존재하지 않습니다."
                });
            }
        }

        private void PlayNextDialogue()
        {
            if (m_loadedDialogues == null)
            {
                return;
            }

            m_currentDialogueIndex++;
            if (m_currentDialogueIndex < m_loadedDialogues.Count)
            {
                PlayDialogueAtIndex(m_currentDialogueIndex);
            }
            else
            {
                m_dialogueVM.NotifyComplete();
                m_dialogueVM.DisplayDialogue(new DialogueDTO
                {
                    Type = DialogueType.SystemMessage,
                    Content = "--- 다이얼로그 테스트 시나리오 종료 ---"
                });
            }
        }

        private void PlayDialogueAtIndex(int index)
        {
            var line = m_loadedDialogues[index];
            DialogueType parsedType = DialogueType.Normal;

            if (line.dialogueType == "Narration")
            {
                parsedType = DialogueType.Narration;
            }
            else if (line.dialogueType == "SystemMessage")
            {
                parsedType = DialogueType.SystemMessage;
            }

            m_dialogueVM.DisplayDialogue(new DialogueDTO
            {
                Type = parsedType,
                SpeakerName = line.speakerName,
                Content = line.content,
                SpeakerIconKey = line.speakerIconKey
            });
        }
    }
}
