using UnityEngine;
using VContainer;
using System.Collections.Generic;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameDialogueOptionsGroupView : MonoBehaviour
    {
        [SerializeField] private List<InGameDialogueOptionCardView> m_optionCards;

        private IDialogueViewModel m_viewModel;

        private void Awake()
        {
            gameObject.SetActive(false);
        }

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnChoicesUpdated += HandleChoicesUpdated;
        }

        private void HandleChoicesUpdated(List<DialogueChoiceDTO> choices)
        {
            if (choices != null && choices.Count > 0)
            {
                gameObject.SetActive(true);

                if (m_optionCards != null)
                {
                    for (int i = 0; i < m_optionCards.Count; i++)
                    {
                        if (m_optionCards[i] != null)
                        {
                            if (i < choices.Count)
                            {
                                m_optionCards[i].gameObject.SetActive(true);
                                m_optionCards[i].SetCardData(choices[i], OnCardSelected);
                            }
                            else
                            {
                                m_optionCards[i].gameObject.SetActive(false);
                            }
                        }
                    }
                }
            }
            else
            {
                gameObject.SetActive(false);
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
