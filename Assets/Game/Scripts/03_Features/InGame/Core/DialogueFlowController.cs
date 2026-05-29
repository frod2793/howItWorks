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
            m_dialogueVM.OnChoiceSelected += HandleChoiceSelected;
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
                var choices = new List<DialogueChoiceDTO>
                {
                    new DialogueChoiceDTO
                    {
                        ChoiceId = 1,
                        Title = "대화하다",
                        Subtitle = "TALK",
                        Description = "지배자의 사연을 듣는다",
                        Condition = "any",
                        IsLocked = false,
                        ColorType = "Yellow"
                    },
                    new DialogueChoiceDTO
                    {
                        ChoiceId = 2,
                        Title = "기억하다",
                        Subtitle = "REMEMBER",
                        Description = "엘레나의 이름 — 회상 트리거",
                        Condition = "C2 -> 진엔딩 +",
                        IsLocked = false,
                        ColorType = "Blue"
                    },
                    new DialogueChoiceDTO
                    {
                        ChoiceId = 3,
                        Title = "느끼다",
                        Subtitle = "FEEL",
                        Description = "감정으로 다가간다 (그리움 활성)",
                        Condition = "C3 -> 진엔딩 ✔",
                        IsLocked = false,
                        ColorType = "Orange"
                    },
                    new DialogueChoiceDTO
                    {
                        ChoiceId = 4,
                        Title = "놓아주다",
                        Subtitle = "LET GO",
                        Description = "회차를 다시 시작한다",
                        Condition = "잠금 — A·B 엔딩 후 활성",
                        IsLocked = true,
                        ColorType = "Gray"
                    }
                };

                m_dialogueVM.DisplayChoices(choices);
            }
        }

        private void HandleChoiceSelected(int choiceId)
        {
            Debug.Log($"[DialogueFlowController] 선택지 {choiceId}번 카드가 처리되었습니다.");
            m_dialogueVM.DisplayDialogue(new DialogueDTO
            {
                Type = DialogueType.SystemMessage,
                Content = $"--- {choiceId}번 선택 결과 진행 완료 ---"
            });
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
