using UnityEngine;
using VContainer;
using System.Collections.Generic;
using System;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameDialogueOptionsManager : MonoBehaviour
    {
        private List<InGameDialogueOptionsGroupView> m_optionGroups;

        private IDialogueViewModel m_viewModel;

        private void Awake()
        {
            var groups = GetComponentsInChildren<InGameDialogueOptionsGroupView>(true);
            if (groups != null)
            {
                m_optionGroups = new List<InGameDialogueOptionsGroupView>(groups);
            }
        }

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnChoicesUpdated += HandleChoicesUpdated;

            if (m_optionGroups != null)
            {
                for (int i = 0; i < m_optionGroups.Count; i++)
                {
                    if (m_optionGroups[i] != null)
                    {
                        m_optionGroups[i].gameObject.SetActive(false);
                    }
                }
            }

            gameObject.SetActive(false);
        }

        private void HandleChoicesUpdated(List<DialogueChoiceDTO> choices)
        {
            if (m_optionGroups != null)
            {
                for (int i = 0; i < m_optionGroups.Count; i++)
                {
                    if (m_optionGroups[i] != null)
                    {
                        m_optionGroups[i].gameObject.SetActive(false);
                    }
                }
            }

            if (choices == null || choices.Count == 0)
            {
                gameObject.SetActive(false);
                return;
            }

            gameObject.SetActive(true);

            int activeIndex = choices.Count - 1;
            if (m_optionGroups != null && activeIndex >= 0 && activeIndex < m_optionGroups.Count)
            {
                var targetGroup = m_optionGroups[activeIndex];
                if (targetGroup != null)
                {
                    targetGroup.gameObject.SetActive(true);
                    targetGroup.SetGroupData(choices, OnCardSelected);
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
