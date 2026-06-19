using UnityEngine;
using VContainer;
using System.Collections.Generic;
using System;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameDialogueOptionsManager : MonoBehaviour
    {
        private List<InGameDialogueOptionCardView> m_optionCards;

        private IDialogueViewModel m_viewModel;

        private void Awake()
        {
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

            gameObject.SetActive(false);
        }

        private void HandleChoicesUpdated(List<DialogueChoiceDTO> choices)
        {
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

            if (choices == null || choices.Count == 0)
            {
                gameObject.SetActive(false);
                return;
            }

            gameObject.SetActive(true);

            if (m_optionCards != null)
            {
                for (int i = 0; i < m_optionCards.Count; i++)
                {
                    if (m_optionCards[i] != null)
                    {
                        if (i < choices.Count)
                        {
                            m_optionCards[i].SetCardData(choices[i], OnCardSelected);
                        }
                        else
                        {
                            m_optionCards[i].Hide();
                        }
                    }
                }
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
