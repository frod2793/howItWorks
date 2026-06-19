using Cysharp.Threading.Tasks;
using System.Collections.Generic;
using System.Text.RegularExpressions;
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
        private SidePanelDTO m_currentSidePanelData;
        private List<ChoiceTriggerDTO> m_choiceTriggers;
        private int m_startDialogueIndex;

        public DialogueFlowController(
            IDialogueViewModel dialogueVM, 
            ISceneInfoViewModel sceneInfoVM, 
            ISidePanelViewModel sidePanelVM, 
            IGameDataManager dataManager,
            int startDialogueIndex)
        {
            m_dialogueVM = dialogueVM;
            m_sceneInfoVM = sceneInfoVM;
            m_sidePanelVM = sidePanelVM;
            m_dataManager = dataManager;
            m_startDialogueIndex = startDialogueIndex;
            m_dialogueVM.OnNextRequested += PlayNextDialogue;
            m_dialogueVM.OnChoiceSelected += HandleChoiceSelected;
        }

        public async UniTaskVoid StartDialogueFlowAsync()
        {
            m_sceneInfoVM.UpdateSceneInfo(new SceneInfoDTO
            {
                ActName = "기(起)",
                SceneNumber = 1,
                SceneTitle = "첫 아침",
                Location = "기숙사",
                TimeOfDay = "낮",
                Playthrough = 1
            });

            m_currentSidePanelData = new SidePanelDTO
            {
                CatoStocks = 2,
                MaxCatoStocks = 5,
                Sadness = 0,
                Joy = 0,
                Curiosity = 0,
                Fear = 0,
                Confusion = 0,
                Monitoring = 0,
                Trust = 0,
                LoopAwareness = 0,
                MaxLoopAwareness = 5,
                ActBranchInfo = "기(起) · A",
                PassedScenesInfo = "씬 1"
            };

            m_sidePanelVM.UpdateSidePanelData(m_currentSidePanelData);

            await m_dataManager.LoadAllDataAsync();
            m_loadedDialogues = m_dataManager.GetDialogueLog();
            m_choiceTriggers = m_dataManager.GetChoiceTriggers();
            m_currentDialogueIndex = m_startDialogueIndex;

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

            if (m_choiceTriggers != null)
            {
                for (int i = 0; i < m_choiceTriggers.Count; i++)
                {
                    if (m_choiceTriggers[i].TriggerDialogueIndex == m_currentDialogueIndex)
                    {
                        ShowDataChoices(m_choiceTriggers[i].Choices);
                        return;
                    }
                }
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
            if (m_choiceTriggers != null)
            {
                for (int i = 0; i < m_choiceTriggers.Count; i++)
                {
                    var trigger = m_choiceTriggers[i];
                    for (int j = 0; j < trigger.Choices.Count; j++)
                    {
                        var choice = trigger.Choices[j];
                        if (choice.ChoiceId == choiceId)
                        {
                            ApplyChoiceResult(choice.Result);
                            return;
                        }
                    }
                }
            }

            m_dialogueVM.DisplayDialogue(new DialogueDTO
            {
                Type = DialogueType.SystemMessage,
                Content = $"--- {choiceId}번 선택 결과 진행 완료 ---"
            });
        }

        private void ShowDataChoices(List<GameChoiceDTO> choices)
        {
            var uiChoices = new List<DialogueChoiceDTO>();
            for (int i = 0; i < choices.Count; i++)
            {
                uiChoices.Add(new DialogueChoiceDTO
                {
                    ChoiceId = choices[i].ChoiceId,
                    Title = choices[i].Title,
                    Subtitle = choices[i].Subtitle,
                    Description = choices[i].Description,
                    Condition = choices[i].Condition,
                    IsLocked = choices[i].IsLocked,
                    ColorType = choices[i].ColorType
                });
            }
            m_dialogueVM.DisplayChoices(uiChoices);
        }

        private void ApplyChoiceResult(ChoiceResultDTO result)
        {
            if (result != null)
            {
                m_currentSidePanelData.CatoStocks += result.CatoDelta;
                m_currentSidePanelData.Monitoring += result.MonitoringDelta;
                m_currentSidePanelData.Curiosity += result.CuriosityDelta;
                m_currentSidePanelData.Confusion += result.ConfusionDelta;
                m_currentSidePanelData.Fear += result.FearDelta;
                m_currentSidePanelData.Sadness += result.SadnessDelta;
                m_currentSidePanelData.Joy += result.JoyDelta;
                m_sidePanelVM.UpdateSidePanelData(m_currentSidePanelData);

                if (!string.IsNullOrEmpty(result.FeedbackMessage))
                {
                    m_dialogueVM.DisplayDialogue(new DialogueDTO
                    {
                        Type = DialogueType.SystemMessage,
                        Content = result.FeedbackMessage
                    });
                }

                m_currentDialogueIndex = result.NextDialogueIndex;
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

            string content = line.content;

            var match = Regex.Match(content, @"^\[씬\s*([^\]:]+?)\s*:\s*([^\]]+?)\]\s*[\r\n]*");
            if (match.Success)
            {
                string sceneCode = match.Groups[1].Value.Trim();
                string sceneTitle = match.Groups[2].Value.Trim();

                int sceneNum = 1;
                var numMatch = Regex.Match(sceneCode, @"\d+");
                if (numMatch.Success)
                {
                    int.TryParse(numMatch.Value, out sceneNum);
                }

                string actName = "기(起)";
                if (sceneNum >= 13)
                {
                    actName = "결(結)";
                }
                else if (sceneNum >= 9)
                {
                    actName = "전(轉)";
                }
                else if (sceneNum >= 4)
                {
                    actName = "승(承)";
                }

                string timeOfDay = "낮";
                if (sceneTitle.Contains("밤") || sceneTitle.Contains("어둠") || sceneTitle.Contains("꿈"))
                {
                    timeOfDay = "밤";
                }

                if (m_sceneInfoVM != null)
                {
                    m_sceneInfoVM.UpdateSceneInfo(new SceneInfoDTO
                    {
                        ActName = actName,
                        SceneNumber = sceneNum,
                        SceneTitle = sceneTitle,
                        Location = sceneCode,
                        TimeOfDay = timeOfDay,
                        Playthrough = 1
                    });
                }

                content = content.Substring(match.Length);
            }

            string trimmedContent = content.Trim();
            if (trimmedContent.StartsWith("(") && trimmedContent.EndsWith(")"))
            {
                parsedType = DialogueType.Narration;
                content = "";
            }

            if (trimmedContent.StartsWith("[비주얼]") || 
                trimmedContent.StartsWith("[카메라]") || 
                trimmedContent.StartsWith("[사운드]") || 
                trimmedContent.StartsWith("[연출 의도]"))
            {
                parsedType = DialogueType.Narration;
                content = "";
            }

            m_dialogueVM.DisplayDialogue(new DialogueDTO
            {
                Type = parsedType,
                SpeakerName = line.speakerName,
                Content = content,
                SpeakerIconKey = line.speakerIconKey,
                CurrentLine = index + 1,
                TotalLines = m_loadedDialogues.Count
            });
        }
    }
}
