using UnityEngine;
using TMPro;
using VContainer;
using Domain.InGame;
using System.Collections.Generic;

namespace Features.InGame
{
    public class InGameMiniDialogueView : MonoBehaviour
    {
        [SerializeField] private TextMeshProUGUI m_nameText;
        [SerializeField] private TextMeshProUGUI m_contentText;

        private IDialogueViewModel m_viewModel;

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnChoicesUpdated += HandleChoicesUpdated;
            gameObject.SetActive(false);
        }

        private void HandleChoicesUpdated(List<DialogueChoiceDTO> choices)
        {
            if (this == null)
            {
                return;
            }
            if (choices != null && choices.Count > 0)
            {
                gameObject.SetActive(true);
                if (m_viewModel.CurrentDialogue != null)
                {
                    if (m_nameText != null)
                    {
                        m_nameText.text = m_viewModel.CurrentDialogue.SpeakerName;
                    }
                    if (m_contentText != null)
                    {
                        m_contentText.text = m_viewModel.CurrentDialogue.Content;
                    }
                }
            }
            else
            {
                gameObject.SetActive(false);
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
