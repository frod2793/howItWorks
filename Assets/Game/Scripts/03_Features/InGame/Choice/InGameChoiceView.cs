using UnityEngine;
using UnityEngine.UI;
using System.Collections.Generic;
using Domain.InGame;
using VContainer;
using TMPro;

namespace Features.InGame
{
    public class InGameChoiceView : MonoBehaviour
    {
        [SerializeField] private RectTransform m_buttonParent;
        [SerializeField] private Button m_choiceButtonPrefab;

        private IChoiceViewModel m_viewModel;
        private List<Button> m_activeButtons = new List<Button>();

        [Inject]
        public void Construct(IChoiceViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnShowChoices += CreateChoiceButtons;
            
            gameObject.SetActive(false);
        }

        private void CreateChoiceButtons(List<ChoiceDTO> choices)
        {
            ClearButtons();
            gameObject.SetActive(true);

            for (int i = 0; i < choices.Count; i++)
            {
                var choice = choices[i];
                var btn = Instantiate(m_choiceButtonPrefab, m_buttonParent);
                var tmp = btn.GetComponentInChildren<TextMeshProUGUI>();
                if (tmp != null)
                {
                    tmp.text = choice.ChoiceText;
                }

                btn.onClick.AddListener(() =>
                {
                    m_viewModel.SelectChoice(choice.ChoiceID);
                    gameObject.SetActive(false);
                });

                m_activeButtons.Add(btn);
            }
        }

        private void ClearButtons()
        {
            for (int i = 0; i < m_activeButtons.Count; i++)
            {
                if (m_activeButtons[i] != null)
                {
                    Destroy(m_activeButtons[i].gameObject);
                }
            }
            m_activeButtons.Clear();
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnShowChoices -= CreateChoiceButtons;
            }
        }
    }
}
