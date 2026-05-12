---
title: "Using Generators to Improve Developer Productivity"
author: "Carlos Cuesta"
source: "Carlos Cuesta"
url: "https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity"
date_saved: "2026-05-12T04:51:39.283Z"
date_published: "2022-05-23 17:55"
word_count: "1451"
reading_time: "8 min"
description: "Let's walk through the experience and the outcome of implementing a tool to generate code. What are the benefits, the problems they solve and how to implement them."
---

# Using Generators to Improve Developer Productivity

A few weeks ago at [N26](http://n26.com/), we did *[get stuff done week](https://medium.com/insiden26/getting-stuff-done-days-at-n26-a70105e6b9c9)*, during this time the product and engineering teams have the opportunity to try or build anything we like.

I decided to spend the week adding a **code generation** tool to the Web project automating a bit of the coding work while improving the developer experience.

In this article, I'll walk through the experience and the outcome of implementing a tool to generate code 👨💻

1.  [What is a code generator?](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#what-is-a-code-generator)
2.  [What's the problem?](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#whats-the-problem)
3.  [Why you should use them?](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#why-you-should-use-them)
    1.  [Developer experience](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#developer-experience)
    2.  [Decision fatigue](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#decision-fatigue)
4.  [Using code generators](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#using-code-generators)
    1.  [Choosing the right tool](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#choosing-the-right-tool)
    2.  [Getting started](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#getting-started)
    3.  [Creating a generator](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#creating-a-generator)
    4.  [Demo](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#demo)
5.  [Automate all the things!](https://carloscuesta.me/blog/using-generators-to-improve-developer-productivity#automate-all-the-things)

### What is a code generator?

A code generator is a tool that given a set of rules and inputs creates code, files, and folders.

To name a few popular ones 👇

-   [create-react-app](http://create-react-app.dev/)
-   [create-next-app](https://nextjs.org/docs/api-reference/create-next-app)
-   [create-react-native-app](https://github.com/expo/create-react-native-app)

All of them will **create code** based on specific **rules** taking into account the **inputs** provided by the **user**. Here's a simple example 👇

![Code generator teaser](https://carloscuesta.me/_next/image?url=https%3A%2F%2Fres.cloudinary.com%2Fcarloscuesta%2Fimage%2Fupload%2Fv1653235448%2Fcode-generators-teaser_hlr2qm.png&w=1536&q=90)

### What's the problem?

Imagine, you start the day working on a new task and you need to create a feature, before writing any code you will need to consider a few things:

-   Folder structure and architecture 📂
-   Naming files convention 📑
-   Where to put the feature 🗂
-   How you should write the tests 🧪

I'm sure the project you're working on has a list of **conventions and patterns defined** that explains how you should work in the codebase.

However, every time you are **going through this process** it **requires** you to **think** 🤔 about those conventions to **make the decision**.

Where is the source of truth? 🧐

-   Documentation 📝
-   [Architecture Decision Records](https://carloscuesta.me/blog/writing-architecture-decision-records) 🏗
-   Similar files on the codebase 🕵️
-   A teammate 🧑💻

As software engineers we work very hard to not repeat code building abstractions, automating manual workflows...

**What about writing code**? In the same way, we advocate for automating processes such as deployments, we should also make an effort to the *non-creative part* of coding such as scaffolding.

### Why you should use them?

Generating code will save you time ⏰ and will increase the productivity of the team 📈

#### Developer experience

In a team that is constantly growing it is important to make sure that everyone is aligned and able to build things efficiently.

[Having a great Developer Experience](https://carloscuesta.me/blog/front-end-tooling-guide-to-improve-developer-experience#the-impact-of-having-a-great-dx) will boost the confidence a developer has with the codebase.

Trust, empowers people to be more productive and agile ⚡️, to name a few of the many benefits you'll get by using generators:

-   Ensure everyone is doing things *"as expected"* according to the project conventions 💖
-   Reduce friction when working with the codebase 🤔
-   Ease the **onboarding** of new joiners 🆕
-   Decrease the development time 🚀

#### Decision fatigue

The most important thing is that your teammates will not have to spend time on *low-value* decisions, such as deciding how a component is structured.

Turns out our decision-making process gets worse the more decisions we make.

This is called [decision fatigue](https://en.wikipedia.org/wiki/Decision_fatigue). For example, Steve Jobs, [limited his everyday clothing](https://www.businessinsider.com/steve-jobs-productivity-hack-reduce-decision-fatigue-psychologists-2021-11) down to one outfit to avoid making a decision.

### Using code generators

Sounds good right 😍? Let's take a look at how we can implement code generators in our project 👀

#### Choosing the right tool

I didn't want to **reinvent the wheel**, my focus was set on the outcome of generating code, not building a tool that solves this problem.

There are a lot of Open Source projects that will do an awesome job generating code. Here's the list of the ones I considered:

-   [Hygen](http://hygen.io/)
-   [Plop](https://plopjs.com/)
-   [Yeoman](https://yeoman.io/)

I decided to go with **Hygen** at N26 because:

-   Great monorepo support
-   Easy to maintain. You'll only need to care about `.EJS` template files and prompts.
-   No configuration required
-   High value with low effort, writing a generator is very simple.

**Plop** is also a great tool but creating a generator is more complex since you need to spend more time writing code and the tool demands extra time on the configuration part compared to Hygen.

**Yeoman** is another valid option, but maintaining generators requires you to manage and publish packages to a registry and I would say the use-case of this tool is more suited to scaffolding projects instead of smaller parts of a codebase.

#### Getting started

It's time to create our code generator 🥳. First, install Hygen as a devDependency in your project:

```sh
$ npm install -D hygen
```

Define a script inside the `package.json` to use the script binary:

```json
{
  "scripts": {
    "generators": "hygen"
  }
}
```

Now we can run Hygen through the `generators` script:

```sh
$ npm run generators
```

After running the command, you'll see that Hygen is telling us we don't have any generators.

```
Error: please specify a generator.
Hygen v6.2.0
```

By default, hygen will read the generator files from a folder named `_templates`.

If you want to change this behavior, create a file named `.hygen.js` at the root level of your project, like this:

```js
const path = require('path')

module.exports = {
  templates: path.join(__dirname, 'generators'),
}
```

#### Creating a generator

A generator is composed of **one or more actions**, every action contains two items:

-   **Templates**: `*.ejs` 🧩
-   **Prompts**: `prompt.js` ⁉️

Let's build a simple generator that creates a React component 🤓. At the end of the post, you'll find a GitHub repository with a lot of different examples 👏

The first thing we need to create is the generator folder that will contain the action:

-   Generator: `component`
-   Action: `react`

```bash
$ mkdir -p generators/component/react
```

##### Templates

Template files define the code that will be created after running the generator, these files are written using a template language called [Embedded JavaScript templates](https://ejs.co/).

Every template starts with a **[frontmatter](https://www.hygen.io/docs/templates/#frontmatter) header**. On this header, you will define the metadata of the template using the [following properties](https://www.hygen.io/docs/templates#all-frontmatter-properties) 🔍

| Property | Type | Usage |
| --- | --- | --- |
| to | String | The destination of the file once compiled. |
| from | String | Use an external file as template. |
| force | Boolean | Overwrite existing files |
| unless\_exists | Boolean | Execute the generator unless file already exists. |
| inject | Boolean | Inject the contents into an existing file instead of creating a new one. |
| after | Regex | Inject the template after the regex |
| before | Regex | Inject the template before the regex |
| prepend | Boolean | Inject the template at the start of the file |
| append | Boolean | Inject the template at the end of the file |
| at\_line | Regex | Inject the template at the specified line number |
| skip\_if | Regex | Skip injection if regex matches. |
| eof\_last | Boolean | Trim the newline from the end of the injection. |
| sh | String | Trigger a shell command after compiling the template |

Now, let's add a template file named `index.ejs` inside the `react` action folder we created previously:

```bash
$ touch generators/component/react/index.ejs
```

As I mentioned before, we want to create a React component, so we need to specify the location of the file where the component is going to be created.

We can do that using the `to` property.

```ejs
---
to: src/components/<%= h.changeCase.pascalCase(name) %>/index.js
---
```

As you can see, we're using a variable called `name` on the header. This value will be provided by the prompts of the generator ⁉️

Then, we need to write the body of the template, where we define the code that will be generated once the template is compiled. I'm reusing the `name` variable in the body as well to create the name and export of the component ✨

```ejs
---
to: src/components/<%= h.changeCase.pascalCase(name) %>/index.js
---

const <%= h.changeCase.pascalCase(name) %> = () => (
  <section>
    <h1>Hey! 👋</h1>
    <h2><code><%= h.changeCase.pascalCase(name) %></code></h2>
  </section>
)

export default <%= h.changeCase.pascalCase(name) %>
```

##### Prompts

In case you need to ask for user input, optionally you can use a prompt file. This is very useful to customize the output of the generator. Prompts are defined using a library named [Enquirer](https://github.com/enquirer/enquirer).

Inside of the same `react` 📁, we will create a `prompt.js` file to ask for the variable defined as `name` in the template:

```js
module.exports = [
  {
    type: 'input',
    name: 'name',
    message: 'Write the name of your component',
  },
]
```

There are a ton of different input types available 🔡, take a [look at this link to get the complete list](https://github.com/enquirer/enquirer#-built-in-prompts).

Now it's time to finally run our generator 🥳 using the script along with the **name** and the **action**:

```
$ npm run generators component react
```

You'll be asked for the prompts and finally the magic will happen! 🦄

![Code generator demo](https://carloscuesta.me/_next/image?url=https%3A%2F%2Fres.cloudinary.com%2Fcarloscuesta%2Fimage%2Fupload%2Fv1653117649%2Fcode-generators-demo_e0ngqz.png&w=1536&q=90)

#### Demo

Take a look at [carloscuesta/codegenerators-demo](https://github.com/carloscuesta/codegenerators-demo) 🕹 if you want to play and see more complex examples!

### Automate all the things!

It's time for you to **find out repetitive tasks** and patterns to **extract them into a generator**! 🚀

I'm very happy with the **productivity boost** and the **consistency** that a tool like this can bring to a team ❤️