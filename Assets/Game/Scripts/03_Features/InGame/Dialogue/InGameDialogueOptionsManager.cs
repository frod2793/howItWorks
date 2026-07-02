using UnityEngine;
using VContainer;
using System.Collections.Generic;
using System;
using Domain.InGame;
using UnityEngine.UI;

namespace Features.InGame
{
    public class InGameDialogueOptionsManager : MonoBehaviour
    {
        private List<InGameDialogueOptionCardView> m_optionCards;
        private IDialogueViewModel m_viewModel;

        private Canvas m_canvas;
        private GraphicRaycaster m_raycaster;

        private void Awake()
        {
            m_canvas = GetComponent<Canvas>();
            m_raycaster = GetComponent<GraphicRaycaster>();

            var cards = GetComponentsInChildren<InGameDialogueOptionCardView>(true);
            if (cards != null)
            {
                m_optionCards = new List<InGameDialogueOptionCardView>(cards);
            }
        }

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnChoicesUpdated += HandleChoicesUpdated;

            if (m_optionCards != null)
            {
                for (int i = 0; i < m_optionCards.Count; i++)
                {
                    if (m_optionCards[i] != null)
                    {
                        m_optionCards[i].gameObject.SetActive(true);
                        m_optionCards[i].Hide();
                    }
                }
            }

            func_SetCanvasActive(false);
        }

        private void HandleChoicesUpdated(List<DialogueChoiceDTO> choices)
        {
            if (this == null)
            {
                return;
            }
            if (m_optionCards != null)
            {
                for (int i = 0; i < m_optionCards.Count; i++)
                {
                    if (m_optionCards[i] != null)
                    {
                        m_optionCards[i].gameObject.SetActive(true);
                        m_optionCards[i].Hide();
                    }
                }
            }

            List<DialogueChoiceDTO> activeChoices = new List<DialogueChoiceDTO>();
            if (choices != null)
            {
                for (int i = 0; i < choices.Count; i++)
                {
                    if (choices[i] != null && !choices[i].IsLocked)
                    {
                        activeChoices.Add(choices[i]);
                    }
                }
            }

            if (activeChoices.Count == 0)
            {
                func_SetCanvasActive(false);
                return;
            }

            func_SetCanvasActive(true);

            if (m_optionCards != null)
            {
                int cardIndex = 0;
                for (int i = 0; i < m_optionCards.Count; i++)
                {
                    if (m_optionCards[i] != null)
                    {
                        if (cardIndex < activeChoices.Count)
                        {
                            m_optionCards[i].SetCardData(activeChoices[cardIndex], OnCardSelected);
                            cardIndex++;
                        }
                        else
                        {
                            m_optionCards[i].Hide();
                        }
                    }
                }
            }
        }

        private void func_SetCanvasActive(bool isActive)
        {
            if (m_canvas != null)
            {
                m_canvas.enabled = isActive;
            }
            if (m_raycaster != null)
            {
                m_raycaster.enabled = isActive;
            }
        }

        private void OnCardSelected(int choiceId)
        {
            if (m_viewModel != null)
            {
                m_viewModel.SelectChoice(choiceId);
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnChoicesUpdated -= HandleChoicesUpdated;
            }
        }
    }
}
